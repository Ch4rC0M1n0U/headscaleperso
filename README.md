# Headscale + Headplane - VPN Self-Hosted Sécurisé

Configuration durcie pour déployer un serveur VPN Tailscale self-hosted avec interface d'administration web.

## 🔒 Mesures de sécurité appliquées

| Protection | Description |
|------------|-------------|
| Endpoints masqués | `/windows`, `/apple`, `/linux`, `/health` → 404 |
| Fingerprinting réduit | Headers serveur supprimés, réponses génériques |
| DERP désactivé | Utilise les relais publics Tailscale (indistinguable) |
| Rate limiting | 50 req/10s par IP via Caddy |
| CrowdSec | Intégration avec bouncer existant |
| Authentik interne | SSO accessible uniquement via VPN |

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
│                    (Scans, attaques)                         │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              CrowdSec Bouncer (niveau firewall)              │
│                 Blocage IPs malveillantes                    │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼ Port 443 (HTTPS uniquement)
┌─────────────────────────────────────────────────────────────┐
│                    Caddy (Reverse Proxy)                     │
│              - Certificat TLS automatique                    │
│              - Rate limiting (50 req/10s)                    │
│              - Endpoints sensibles → 404                     │
│              - Headers nettoyés                              │
└──────────┬─────────────────────────────────────┬────────────┘
           │ /admin/*                            │ protocole Tailscale
           ▼                                     ▼
┌──────────────────────┐        ┌──────────────────────────────┐
│     Headplane        │        │         Headscale            │
│   (Interface Web)    │◄──────►│   (Coordination VPN)         │
└──────────────────────┘        │   DERP désactivé             │
                                │   Relais Tailscale publics   │
                                └──────────────────────────────┘
                                             │
                                             │ Tailnet (100.64.0.0/10)
                    ┌────────────────────────┼────────────────────────┐
                    │                        │                        │
                    ▼                        ▼                        ▼
             ┌─────────────┐          ┌─────────────┐          ┌─────────────┐
             │  Authentik  │          │   Clients   │          │   Services  │
             │  (interne)  │          │   OSINT     │          │   internes  │
             │ 100.64.0.X  │          │             │          │             │
             └─────────────┘          └─────────────┘          └─────────────┘
```

## 📋 Prérequis

- Docker et Docker Compose
- Serveur Hetzner avec CrowdSec installé
- Ports 80 et 443 ouverts

## 🚀 Installation

```bash
# 1. Extraire l'archive sur le serveur
cd /opt
tar -xzf headscale-setup.tar.gz
cd headscale-setup

# 2. Lancer l'installation
./manage.sh install
```

Le script génère automatiquement la clé API initiale.

**URL d'accès** : `https://static.45.211.62.46.clients.your-server.de:8443/admin`

## 📖 Commandes disponibles

```bash
./manage.sh install    # Installation initiale
./manage.sh start      # Démarrer les services
./manage.sh stop       # Arrêter les services
./manage.sh restart    # Redémarrer les services
./manage.sh status     # Statut des services
./manage.sh logs       # Voir les logs (tous)
./manage.sh logs headscale  # Logs Headscale uniquement
./manage.sh apikey     # Créer une clé API
./manage.sh user       # Créer un utilisateur
./manage.sh preauth    # Créer une clé pré-auth
./manage.sh nodes      # Lister les nodes
./manage.sh backup     # Sauvegarder
./manage.sh update     # Mettre à jour les images
```

## 🔑 Premier accès

1. Accédez à `https://static.45.211.62.46.clients.your-server.de:8443/admin`
2. Entrez la clé API affichée lors de l'installation
3. Créez un utilisateur : `./manage.sh user`

## 💻 Connecter un client

### Linux
```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --login-server https://static.45.211.62.46.clients.your-server.de:8443 --authkey VOTRE_PREAUTH_KEY
```

### Windows (PowerShell Admin)
```powershell
# Après installation de Tailscale
tailscale up --login-server https://static.45.211.62.46.clients.your-server.de:8443 --authkey VOTRE_PREAUTH_KEY
```

### macOS
```bash
brew install tailscale
tailscale up --login-server https://static.45.211.62.46.clients.your-server.de:8443 --authkey VOTRE_PREAUTH_KEY
```

### Android / iOS
1. Installez l'app Tailscale
2. Menu ⋮ → Settings → Accounts → Use custom coordination server
3. URL: `https://static.45.211.62.46.clients.your-server.de:8443`

## 📁 Structure

```
headscale-setup/
├── docker-compose.yml
├── manage.sh
├── docs/
│   ├── AUTHENTIK-SETUP.md    # Guide SSO Authentik
│   └── CROWDSEC-INTEGRATION.md
├── headscale/
│   └── config/
│       ├── config.yaml
│       └── dns_records.json
├── headplane/
│   └── config/
│       └── config.yaml
└── caddy/
    └── Caddyfile
```

## 📚 Documentation complémentaire

- `docs/AUTHENTIK-SETUP.md` - Configuration SSO avec Authentik (interne VPN)
- `docs/CROWDSEC-INTEGRATION.md` - Intégration CrowdSec

## 🆘 Dépannage

```bash
# Voir les logs
./manage.sh logs

# Vérifier le statut
./manage.sh status

# Tester la connectivité depuis un client
tailscale status
tailscale ping <autre-node>
```

---
*Configuration sécurisée - Police Judiciaire Fédérale - DR5-OA5 OSINT*
