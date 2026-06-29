# GitLab CE Server

Selbst-gehostete GitLab Community Edition als VM-Deployment mit automatisch angelegten Studierenden-Accounts und optionalen GitLab-internen Gruppen.

## Konzept

Eine GitLab-Instanz pro Deploy — alle Studierenden und der Dozent werden automatisch als GitLab-User angelegt. Optional können Studierende in GitLab-Gruppen organisiert werden (z.B. Projektgruppen), die der Dozent als Owner verwaltet.

**Deploy-Strategie:** Nur `one-instance`. GitLab ist von Haus aus Multi-User — eine Instanz pro Kurs reicht.

## Parameter

### Allgemein

| Parameter | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `app_name` | string | ja | Identifier der Instanz |
| `admin_username` | email (user-picker) | ja | Dozent → GitLab-Root-Admin |
| `students` | list(email) (user-picker, multi) | ja | Studierende, werden als GitLab-User angelegt (1-30) |

### GitLab-Optionen

| Parameter | Typ | Default | Beschreibung |
|---|---|---|---|
| `flavor_name` | selection | `gp1.large` | VM-Größe (Large empfohlen, GitLab braucht ≥ 4 GB RAM) |
| `gitlab_version` | string | `17.0.8-ce.0` | GitLab CE Paketversion |
| `gitlab_groups` | groups (group-builder) | `{}` | Optional: GitLab-interne Gruppen mit Mitgliedern |

## Outputs

| Output | Sichtbar | Sensitive | Beschreibung |
|---|---|---|---|
| `instance_id` | nein | nein | VM-ID (intern) |
| `app_name` | ja | nein | Projektname |
| `gitlab_url` | ja | nein | `http://<floating-ip>` |
| `ssh_command` | ja | nein | SSH-Vorlage (Key benötigt) |
| `admin_credentials` | nein | ja | Dozenten-Login (GitLab Root) |
| `student_credentials` | nein | ja | Map email → {username, email, password, gitlab_url} |
| `ssh_private_key` | nein | ja | SSH Private Key (für VM-Zugang, RSA 4096) |

## Setup-Ablauf (cloud-init)

1. Ubuntu 22.04 Base + Pakete (`curl`, `ca-certificates`, `postfix`, `ufw`)
2. UFW: Ports 22, 80
3. GitLab CE Repository einbinden
4. GitLab CE in spezifizierter Version installieren
5. `external_url` in `gitlab.rb` auf Floating-IP setzen, `gitlab-ctl reconfigure`
6. **Systemd-Service** `cloudstore-gitlab-setup.service` wartet bis GitLab Rails bereit ist und legt dann via `gitlab-rails runner` an:
   - Root-Passwort setzen
   - Dozenten-Account (Admin)
   - Alle Studierenden-Accounts
   - GitLab-Gruppen + Mitglieder (Studierende als Developer, Dozent als Owner)

## Username-Konvention

E-Mails werden zu GitLab-Usernames konvertiert. Der lokale Teil bleibt, jedes Domain-Token wird auf max. 2 Zeichen gekürzt (hält den Username unter 32 Zeichen).

| Email | Username |
|---|---|
| `s2327001@student.dhbw-mannheim.de` | `s2327001_st_dh-ma_de` |
| `prof1@dhbw-mannheim.de` | `prof1_dh-ma_de` |

## Zugriff

### Studierende

1. Web-Login unter `gitlab_url` mit Username + Passwort aus `student_credentials[<eigene-email>]`
2. Optional Mitglied in einer der `gitlab_groups` (Developer-Rolle)
3. Eigener Namespace für persönliche Projekte verfügbar

### Dozent (Admin)

1. **Web-UI als Admin:** Login mit `admin_credentials.username` / `admin_credentials.password` → Admin-Bereich verfügbar
2. **GitLab Root-Login** (falls nötig): Username `root`, Passwort = `admin_credentials.password` (gleiches Passwort wie Dozenten-Account)
3. **VM per SSH:**
   ```bash
   ssh -i ./key.pem ubuntu@<floating-ip>
   sudo gitlab-rails console        # Direkt-Zugriff auf GitLab-Datenbank
   sudo gitlab-ctl status           # Service-Status
   sudo gitlab-ctl reconfigure      # Konfig neu anwenden
   ```

### Typische Admin-Aufgaben

```bash
# User-Passwort zurücksetzen (auf der VM, via Rails Runner)
sudo gitlab-rails runner "User.find_by(email: 'student@x.de').update(password: 'NewSecret123', password_confirmation: 'NewSecret123')"

# GitLab-Logs anschauen
sudo gitlab-ctl tail

# Service neustarten
sudo gitlab-ctl restart
```

## Ports

| Port | Zweck |
|---|---|
| 22 | SSH (Admin-Zugang) |
| 80 | GitLab Web UI (HTTP) |

HTTPS ist standardmäßig nicht konfiguriert — für Produktiv-Setups Reverse-Proxy oder GitLab-internes Let's-Encrypt aktivieren.

## Ressourcenbedarf

GitLab CE ist ressourcenintensiv:

- **Mindestens** `gp1.medium` (4 GB RAM) — sonst OOM-Killer
- **Empfohlen** `gp1.large` (8 GB RAM) für reibungsloses Arbeiten mit mehreren parallelen Nutzern
- Boot + Setup dauert ca. **5-10 Minuten** (GitLab Reconfigure + User-Anlage)
