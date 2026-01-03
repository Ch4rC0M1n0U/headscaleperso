#!/bin/bash
###############################################################################
# Script de déploiement et gestion Headscale + Headplane
# Police Judiciaire Fédérale - DR5-OA5 OSINT
###############################################################################

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Fonctions utilitaires
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Afficher l'aide
show_help() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  install       - Installation initiale (configure le domaine)"
    echo "  start         - Démarrer tous les services"
    echo "  stop          - Arrêter tous les services"
    echo "  restart       - Redémarrer tous les services"
    echo "  status        - Afficher le statut des services"
    echo "  logs          - Afficher les logs (optionnel: logs headscale)"
    echo "  apikey        - Créer une nouvelle clé API Headscale"
    echo "  user          - Créer un nouvel utilisateur"
    echo "  preauth       - Créer une clé pré-authentification"
    echo "  nodes         - Lister les nodes connectés"
    echo "  backup        - Sauvegarder la configuration et les données"
    echo "  update        - Mettre à jour les images Docker"
    echo "  uninstall     - Supprimer tous les containers et volumes"
    echo ""
}

# Installation initiale
install() {
    log_info "Installation de Headscale + Headplane"
    log_info "Domaine configuré: static.45.211.62.46.clients.your-server.de"
    echo ""
    
    # Générer un nouveau cookie secret
    NEW_SECRET=$(openssl rand -hex 16)
    
    # Mettre à jour le cookie secret dans Headplane
    sed -i "s|cookie_secret: \".*\"|cookie_secret: \"$NEW_SECRET\"|g" headplane/config/config.yaml
    log_success "Cookie secret généré"
    
    # Créer les dossiers de données
    mkdir -p headscale/data headplane/data caddy/data caddy/config
    
    # Définir les permissions
    chmod 700 headscale/data headplane/data
    
    # Démarrer les services
    log_info "Démarrage des services..."
    docker compose up -d
    
    # Attendre que Headscale soit prêt
    log_info "Attente du démarrage de Headscale..."
    sleep 15
    
    # Créer la première clé API
    log_info "Création de la clé API initiale..."
    API_KEY=$(docker exec headscale headscale apikeys create --expiration 365d 2>/dev/null || echo "")
    
    if [ -n "$API_KEY" ]; then
        echo ""
        log_success "Installation terminée!"
        echo ""
        echo "=========================================="
        echo -e "${GREEN}Votre clé API Headscale:${NC}"
        echo -e "${YELLOW}$API_KEY${NC}"
        echo "=========================================="
        echo ""
        echo "Conservez cette clé précieusement!"
        echo ""
        echo "Accédez à Headplane: https://static.45.211.62.46.clients.your-server.de/admin"
        echo ""
        echo "Prochaines étapes:"
        echo "  1. Créer un utilisateur: ./manage.sh user"
        echo "  2. Créer une clé pré-auth: ./manage.sh preauth"
        echo "  3. Connecter vos clients Tailscale"
        echo "  4. Configurer Authentik (voir docs/AUTHENTIK-SETUP.md)"
        echo ""
    else
        log_warning "Impossible de créer la clé API automatiquement"
        log_info "Exécutez: $0 apikey"
    fi
}

# Démarrer les services
start() {
    log_info "Démarrage des services..."
    docker compose up -d
    log_success "Services démarrés"
}

# Arrêter les services
stop() {
    log_info "Arrêt des services..."
    docker compose down
    log_success "Services arrêtés"
}

# Redémarrer les services
restart() {
    log_info "Redémarrage des services..."
    docker compose restart
    log_success "Services redémarrés"
}

# Statut des services
status() {
    docker compose ps
}

# Afficher les logs
logs() {
    if [ -n "$1" ]; then
        docker compose logs -f "$1"
    else
        docker compose logs -f
    fi
}

# Créer une clé API
apikey() {
    read -p "Durée d'expiration (ex: 90d, 365d): " EXPIRY
    EXPIRY=${EXPIRY:-90d}
    
    log_info "Création d'une clé API (expiration: $EXPIRY)..."
    docker exec headscale headscale apikeys create --expiration "$EXPIRY"
}

# Créer un utilisateur
user() {
    read -p "Nom de l'utilisateur: " USERNAME
    if [ -z "$USERNAME" ]; then
        log_error "Le nom d'utilisateur ne peut pas être vide"
        exit 1
    fi
    
    log_info "Création de l'utilisateur: $USERNAME"
    docker exec headscale headscale users create "$USERNAME"
    log_success "Utilisateur créé"
}

# Créer une clé pré-auth
preauth() {
    # Lister les utilisateurs
    log_info "Utilisateurs disponibles:"
    docker exec headscale headscale users list
    echo ""
    
    read -p "Nom de l'utilisateur: " USERNAME
    read -p "Réutilisable (y/n): " REUSABLE
    read -p "Ephemeral (y/n): " EPHEMERAL
    read -p "Durée d'expiration (ex: 1h, 24h, 7d): " EXPIRY
    
    OPTS=""
    [ "$REUSABLE" = "y" ] && OPTS="$OPTS --reusable"
    [ "$EPHEMERAL" = "y" ] && OPTS="$OPTS --ephemeral"
    EXPIRY=${EXPIRY:-24h}
    
    log_info "Création de la clé pré-auth..."
    docker exec headscale headscale preauthkeys create --user "$USERNAME" --expiration "$EXPIRY" $OPTS
}

# Lister les nodes
nodes() {
    docker exec headscale headscale nodes list
}

# Sauvegarde
backup() {
    BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    log_info "Sauvegarde en cours..."
    
    # Copier les configurations
    cp -r headscale/config "$BACKUP_DIR/headscale-config"
    cp -r headplane/config "$BACKUP_DIR/headplane-config"
    cp caddy/Caddyfile "$BACKUP_DIR/Caddyfile"
    
    # Sauvegarder la base de données Headscale
    docker exec headscale cp /var/lib/headscale/db.sqlite /tmp/db.sqlite
    docker cp headscale:/tmp/db.sqlite "$BACKUP_DIR/headscale.sqlite"
    
    # Créer l'archive
    tar -czf "$BACKUP_DIR.tar.gz" -C "$(dirname $BACKUP_DIR)" "$(basename $BACKUP_DIR)"
    rm -rf "$BACKUP_DIR"
    
    log_success "Sauvegarde créée: $BACKUP_DIR.tar.gz"
}

# Mise à jour
update() {
    log_info "Mise à jour des images Docker..."
    docker compose pull
    docker compose up -d
    log_success "Mise à jour terminée"
}

# Désinstallation
uninstall() {
    log_warning "Cette action va supprimer tous les containers et données!"
    read -p "Êtes-vous sûr? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" = "yes" ]; then
        docker compose down -v
        log_success "Désinstallation terminée"
    else
        log_info "Annulé"
    fi
}

# Main
case "${1:-help}" in
    install)  install ;;
    start)    start ;;
    stop)     stop ;;
    restart)  restart ;;
    status)   status ;;
    logs)     logs "$2" ;;
    apikey)   apikey ;;
    user)     user ;;
    preauth)  preauth ;;
    nodes)    nodes ;;
    backup)   backup ;;
    update)   update ;;
    uninstall) uninstall ;;
    help|*)   show_help ;;
esac
