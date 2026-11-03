# Action Plan: Panduan Menjalankan DevSecOps Home Test

Panduan langkah demi langkah agar Anda bisa menjalankan, menguji, dan memamerkan proyek ini secara mandiri—baik di komputer lokal (Windows/Mac) maupun di **VPS Ubuntu**.

---

## Ringkasan Langkah Cepat
1. **Pilih lingkungan**: Komputer lokal atau **VPS Ubuntu** (Direkomendasikan)
2. **Jalankan aplikasi**: Node.js & Docker container
3. **Eksekusi 6 tool keamanan**: Gitleaks, SonarQube, Trivy FS, Checkov, Trivy Image, ZAP
4. **Buka Laporan**: File Markdown & Dasbor HTML (`evidence/security-report.html`)
5. **Push ke GitLab / GitHub**: Aktifkan pipeline otomatis

---

## Jalur A: Menguji di VPS Ubuntu (Sangat Direkomendasikan! 🚀)

Menguji di VPS Ubuntu memberikan pengalaman paling realistis karena seluruh CI/CD Runner di dunia kerja (GitLab Runner / GitHub Actions) berjalan di atas Linux Ubuntu.

### 1. Persiapan VPS Ubuntu (Hanya Sekali)
Login ke VPS via SSH, lalu pastikan Docker terpasang:
```bash
# Update package list & install Docker
sudo apt update && sudo apt install -y docker.io git curl

# Izinkan user menjalankan docker tanpa sudo (opsional)
sudo usermod -aG docker $USER
newgrp docker

# Verifikasi docker aktif
docker --version
```

### 2. Pindahkan / Clone Project ke VPS
Cara termudah adalah via Git (setelah di-push ke GitHub/GitLab), atau transfer langsung dari laptop Anda menggunakan `scp`:
```bash
# Dari terminal laptop Anda:
scp -r devsecops-home-test user@IP_VPS_ANDA:~/devsecops-home-test
```
Atau jika sudah di-push ke Git, langsung clone di VPS:
```bash
git clone https://github.com/<username-anda>/devsecops-home-test.git
cd devsecops-home-test
```

### 3. Build & Verifikasi Hardened Container di VPS
```bash
# Build image
docker build -t devsecops-backend-api:latest ./app

# Verifikasi user non-root (output harus: node, bukan root)
docker run --rm devsecops-backend-api:latest whoami
```

### 4. Jalankan Seluruh Tool Keamanan di VPS
Semua scanner berjalan cepat di VPS Linux karena koneksi data centernya cepat:

```bash
# 1. Secret Scanning (Gitleaks)
docker run --rm -v "$(pwd):/path" zricethezav/gitleaks:latest detect --source="/path" -v

# 2. SCA Dependency Scan (Trivy FS)
docker run --rm -v "$(pwd)/app:/root" aquasec/trivy:latest fs --severity HIGH,CRITICAL /root

# 3. IaC Scan (Checkov)
docker run --rm -v "$(pwd)/terraform:/tf" bridgecrew/checkov:latest -d /tf --framework terraform

# 4. Container Vulnerability Scan (Trivy Image)
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image \
  --severity HIGH,CRITICAL --exit-code 1 devsecops-backend-api:latest

# 5. DAST (OWASP ZAP)
# Nyalakan backend di background
docker run -d --name test-api -p 8080:8080 devsecops-backend-api:latest
# Jalankan ZAP scanner
docker run --rm --network="host" -t zaproxy/zap-stable:latest zap-baseline.py \
  -t http://127.0.0.1:8080 -r zap-report.html -I
# Bersihkan container test
docker rm -f test-api
```

### 5. Cara Melihat Laporan HTML dari VPS
Di dalam VPS, Anda bisa menyalakan web server sederhana dengan satu perintah:
```bash
cd ~/devsecops-home-test/evidence
python3 -m http.server 8000
```
Buka browser di laptop Anda: `http://IP_VPS_ANDA:8000/security-report.html` untuk melihat dasbor laporan keamanan langsung!

---

## Jalur B: Menguji di Komputer Lokal (Windows)

Jika Anda ingin menguji langsung di laptop lokal sebelum ke VPS:

### 1. Jalankan Aplikasi
```bash
cd devsecops-home-test/app
npm install
node src/app.js
# Uji di browser: http://localhost:8080/healthz
```

### 2. Build Container Docker
Pastikan Docker Desktop aktif di Windows:
```bash
cd devsecops-home-test
docker build -t devsecops-backend-api:latest ./app
docker run --rm devsecops-backend-api:latest whoami
```

### 3. Eksekusi Scanner Lokal via Docker
```powershell
# Gitleaks
docker run --rm -v "${PWD}:/path" zricethezav/gitleaks:latest detect --source="/path" -v

# Trivy FS (SCA)
docker run --rm -v "${PWD}/app:/root" aquasec/trivy:latest fs --severity HIGH,CRITICAL /root

# Checkov (IaC)
docker run --rm -v "${PWD}/terraform:/tf" bridgecrew/checkov:latest -d /tf --framework terraform

# Trivy Container Scan
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL --exit-code 1 devsecops-backend-api:latest
```

---

## Langkah 4: Setup SonarQube (Lokal atau Cloud)

Untuk memenuhi kebutuhan SAST SonarQube pada Task 2:

### Opsi A: SonarCloud (Paling Praktis untuk CI/CD)
1. Buka [sonarcloud.io](https://sonarcloud.io) (Login via GitHub/GitLab).
2. Buat organisasi & project baru dengan key: `devsecops-backend-api`.
3. Dapatkan Token, lalu scan dari terminal:
```bash
docker run --rm -v "$(pwd):/usr/src" sonarsource/sonar-scanner-cli \
  -Dsonar.projectKey=devsecops-backend-api \
  -Dsonar.host.url="https://sonarcloud.io" \
  -Dsonar.token="<TOKEN_ANDA>"
```

### Opsi B: SonarQube Server Mandiri (di VPS Ubuntu)
Jika VPS Anda punya RAM minimal 4 GB, Anda bisa pasang SonarQube server sendiri:
```bash
docker run -d --name sonarqube -p 9000:9000 sonarqube:lts-community
```
Buka `http://IP_VPS_ANDA:9000` (User: `admin`, Pass: `admin`).

---

## Langkah 5: Push ke GitHub / GitLab untuk Trigger Pipeline

Agar ke-8 tahapan security pipeline berjalan otomatis setiap ada commit:

```bash
cd devsecops-home-test
git init
git add .
git commit -m "feat: complete devsecops reference architecture with sonarqube"

# Ke GitHub:
git remote add origin https://github.com/<username-anda>/devsecops-home-test.git
git branch -M main
git push -u origin main

# Ke GitLab:
git remote add origin https://gitlab.com/<username-anda>/devsecops-home-test.git
git branch -M main
git push -u origin main
```

Di repository GitLab/GitHub:
- Tambahkan secrets: `SONAR_HOST_URL` dan `SONAR_TOKEN`.
- Pipeline akan otomatis aktif dan memvalidasi seluruh security gate!
