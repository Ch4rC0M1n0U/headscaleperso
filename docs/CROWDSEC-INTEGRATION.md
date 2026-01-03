# Intégration CrowdSec avec Headscale

## Architecture

CrowdSec est déjà installé sur ton serveur Hetzner. L'intégration se fait à deux niveaux :

```
┌─────────────────────────────────────────────────────────────┐
│                    Trafic entrant                            │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              CrowdSec Bouncer (iptables/nftables)           │
│                    Blocage au niveau IP                      │
│              ✓ IPs malveillantes connues                    │
│              ✓ Scanneurs détectés                           │
└─────────────────────────┬───────────────────────────────────┘
                          │ (trafic filtré)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                     Caddy (rate limit)                       │
│              ✓ Rate limiting par IP                          │
│              ✓ Endpoints bloqués (404)                       │
│              ✓ Headers nettoyés                              │
└─────────────────────────────────────────────────────────────┘
```

## Configuration CrowdSec pour Headscale

### 1. Ajouter les logs Caddy à CrowdSec

Éditer `/etc/crowdsec/acquis.yaml` sur l'hôte :

```yaml
# Logs Caddy pour Headscale
filenames:
  - /opt/headscale-setup/caddy/data/access.log
labels:
  type: caddy
---
```

### 2. Installer le parser Caddy (si pas déjà fait)

```bash
cscli parsers install crowdsecurity/caddy-logs
cscli collections install crowdsecurity/caddy
```

### 3. Scénarios de détection recommandés

```bash
# Détection des scans HTTP
cscli scenarios install crowdsecurity/http-probing
cscli scenarios install crowdsecurity/http-bad-user-agent
cscli scenarios install crowdsecurity/http-crawl-non_statics
cscli scenarios install crowdsecurity/http-sensitive-files

# Brute force générique
cscli scenarios install crowdsecurity/http-bf-wordpress_bf  # adapté aux tentatives de login
```

### 4. Redémarrer CrowdSec

```bash
systemctl restart crowdsec
```

## Vérification

### Voir les décisions actives
```bash
cscli decisions list
```

### Voir les alertes récentes
```bash
cscli alerts list
```

### Tester manuellement un ban
```bash
# Bannir une IP de test
cscli decisions add -i 192.168.1.100 -r "test manual ban"

# Vérifier
cscli decisions list

# Supprimer
cscli decisions delete -i 192.168.1.100
```

## Scénario personnalisé pour Headscale

Créer `/etc/crowdsec/scenarios/headscale-scan.yaml` :

```yaml
type: trigger
name: custom/headscale-scan
description: "Détecte les tentatives d'identification Headscale"
filter: evt.Meta.log_type == 'http_access-log' && evt.Meta.http_path in ['/windows', '/apple', '/linux', '/health', '/version', '/metrics']
groupby: evt.Meta.source_ip
capacity: 5
leakspeed: 30s
blackhole: 2m
labels:
  service: headscale
  type: scan
  remediation: true
```

Puis :
```bash
cscli scenarios install ./headscale-scan.yaml --local
systemctl restart crowdsec
```

## Dashboard CrowdSec (optionnel)

Si tu veux visualiser les métriques, tu peux enregistrer ton instance :

```bash
cscli console enroll <ta-clé>
```

Dashboard : https://app.crowdsec.net/

---

## Note importante

Le bouncer firewall (iptables/nftables) bloque au niveau réseau AVANT que le trafic n'atteigne Docker/Caddy. C'est plus efficace que de bloquer au niveau applicatif.

Vérifie que ton bouncer est actif :
```bash
cscli bouncers list
```
