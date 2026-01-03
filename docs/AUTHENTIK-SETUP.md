# Configuration Authentik pour Headscale + Headplane

## Architecture de sécurité

```
┌─────────────────────────────────────────────────────────────────────┐
│                          INTERNET                                    │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼ Port 443 (HTTPS)
┌─────────────────────────────────────────────────────────────────────┐
│              Headscale (static.45.211.62.46...)                      │
│                    Coordination VPN                                  │
│         ✓ Exposé sur Internet (nécessaire)                          │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │   Tailnet VPN       │
                    │   100.64.0.0/10     │
                    └──────────┬──────────┘
                               │
           ┌───────────────────┼───────────────────┐
           │                   │                   │
           ▼                   ▼                   ▼
    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
    │  Authentik  │     │  Headplane  │     │   Autres    │
    │  (interne)  │     │   (admin)   │     │  services   │
    │ 100.64.0.X  │     │             │     │  internes   │
    └─────────────┘     └─────────────┘     └─────────────┘
```

**Principe** : Authentik n'est JAMAIS exposé sur Internet. 
Pour se connecter avec OIDC, l'utilisateur doit d'abord être sur le VPN.

---

## Étape 1 : Connecter Authentik au Tailnet

Sur le serveur Authentik, installer le client Tailscale :

```bash
# Installer Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Connecter au Headscale (remplacer YOUR_PREAUTH_KEY)
tailscale up --login-server https://static.45.211.62.46.clients.your-server.de \
  --authkey YOUR_PREAUTH_KEY \
  --hostname authentik
```

Vérifier l'IP Tailnet attribuée :
```bash
tailscale ip -4
# Exemple: 100.64.0.2
```

---

## Étape 2 : Ajouter un record DNS dans Headscale

Dans l'interface Headplane (DNS → Extra Records), ajouter :

```json
[
  {
    "name": "authentik.tailnet.local",
    "type": "A",
    "value": "100.64.0.2"
  }
]
```

Ou via le fichier `dns_records.json` :
```json
[
  {"name": "authentik.tailnet.local", "type": "A", "value": "100.64.0.2"}
]
```

---

## Étape 3 : Créer les applications dans Authentik

### Application Headscale

1. **Admin Authentik** → Applications → Create
2. **Name**: `Headscale`
3. **Slug**: `headscale`
4. **Provider**: Create new → OAuth2/OpenID Provider

**Configuration du Provider Headscale** :
| Paramètre | Valeur |
|-----------|--------|
| Name | Headscale OIDC |
| Authorization flow | default-provider-authorization-implicit-consent |
| Client type | Confidential |
| Client ID | `headscale` |
| Client Secret | (générer et noter) |
| Redirect URIs | `https://static.45.211.62.46.clients.your-server.de:8443/oidc/callback` |
| Scopes | openid, email, profile |

### Application Headplane

1. **Admin Authentik** → Applications → Create
2. **Name**: `Headplane`
3. **Slug**: `headplane`
4. **Provider**: Create new → OAuth2/OpenID Provider

**Configuration du Provider Headplane** :
| Paramètre | Valeur |
|-----------|--------|
| Name | Headplane OIDC |
| Authorization flow | default-provider-authorization-implicit-consent |
| Client type | Confidential |
| Client ID | `headplane` |
| Client Secret | (générer et noter) |
| Redirect URIs | `https://static.45.211.62.46.clients.your-server.de:8443/admin/oidc/callback` |
| Scopes | openid, email, profile |

---

## Étape 4 : Configurer les secrets

Sur le serveur Headscale, créer les fichiers de secrets :

```bash
# Secret OIDC pour Headscale
echo "VOTRE_CLIENT_SECRET_HEADSCALE" > /opt/headscale-setup/headscale/data/oidc_secret
chmod 600 /opt/headscale-setup/headscale/data/oidc_secret

# Secret OIDC pour Headplane
echo "VOTRE_CLIENT_SECRET_HEADPLANE" > /opt/headscale-setup/headplane/data/oidc_secret
chmod 600 /opt/headscale-setup/headplane/data/oidc_secret
```

---

## Étape 5 : Mettre à jour les configurations

### headscale/config/config.yaml

Vérifier/ajuster l'URL issuer avec l'IP Tailnet d'Authentik :

```yaml
oidc:
  only_start_if_oidc_is_available: false
  issuer: "http://100.64.0.2/application/o/headscale/"  # IP Tailnet Authentik
  # OU avec MagicDNS :
  # issuer: "http://authentik.tailnet.local/application/o/headscale/"
  client_id: "headscale"
  client_secret_path: "/var/lib/headscale/oidc_secret"
```

### headplane/config/config.yaml

```yaml
oidc:
  issuer: "http://100.64.0.2/application/o/headplane/"  # IP Tailnet Authentik
  # OU avec MagicDNS :
  # issuer: "http://authentik.tailnet.local/application/o/headplane/"
  client_id: "headplane"
  client_secret_path: "/var/lib/headplane/oidc_secret"
  redirect_uri: "https://static.45.211.62.46.clients.your-server.de:8443/admin/oidc/callback"
  disable_api_key_login: false
```

---

## Étape 6 : Redémarrer les services

```bash
cd /opt/headscale-setup
./manage.sh restart
```

---

## Workflow de connexion

### Premier accès (Admin)
1. Se connecter au VPN avec une clé pré-auth
2. Aller sur `https://static.45.211.62.46.clients.your-server.de:8443/admin`
3. Se connecter avec la clé API Headscale
4. Configurer les utilisateurs et ACL

### Accès utilisateur (après config OIDC)
1. Se connecter au VPN (Tailscale client + clé pré-auth)
2. Aller sur `https://static.45.211.62.46.clients.your-server.de:8443/admin`
3. Cliquer "Login with OIDC"
4. Être redirigé vers Authentik (accessible via VPN uniquement)
5. S'authentifier
6. Être redirigé vers Headplane

---

## Sécurité supplémentaire (optionnel)

### Limiter l'accès OIDC à certains groupes Authentik

Dans `headscale/config/config.yaml` :
```yaml
oidc:
  # ... autres options ...
  allowed_groups:
    - "headscale-admins"
    - "osint-team"
```

### Créer les groupes dans Authentik

1. Directory → Groups → Create
2. Name: `headscale-admins` / `osint-team`
3. Ajouter les utilisateurs appropriés

---

## Dépannage

### "OIDC issuer not reachable"
→ Vérifier que le serveur peut résoudre l'adresse Authentik via le Tailnet
```bash
tailscale ping authentik
curl http://100.64.0.2/application/o/headscale/.well-known/openid-configuration
```

### "Invalid redirect URI"
→ Vérifier que l'URI dans Authentik correspond exactement à celle configurée

### "Access denied"
→ Vérifier les groupes autorisés et l'appartenance de l'utilisateur

---

## Notes importantes

⚠️ **Authentik doit être accessible en HTTP** depuis le Tailnet (pas HTTPS) car c'est du trafic interne chiffré par WireGuard.

⚠️ **Le navigateur de l'utilisateur doit être sur le VPN** pour accéder à Authentik lors de l'authentification OIDC.

⚠️ **Garder `disable_api_key_login: false`** pour avoir un accès de secours si OIDC échoue.
