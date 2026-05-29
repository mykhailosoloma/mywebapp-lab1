# Звіт — Лабораторна робота №2. Контейнеризація

**Середовище:** Ubuntu 24.04, Docker 29.5.2, Docker Compose v5.1.4, 1 vCPU, 2 GB RAM

---

## 1.1 Python Application

Проект: https://github.com/KPI-FICT-MTSD/lab-03-starter-project-python

### Результати

| Образ | Базовий | Розмір | Час (1-й) | Час (кеш) |
|-------|---------|--------|-----------|-----------|
| spaceship:v1 | bookworm | 1570 MB | 139 s | — |
| spaceship:v2 | bookworm | 1570 MB | — | 97 s |
| spaceship:v3 (оптимізований) | bookworm | 1570 MB | 128 s | ~11 s |
| spaceship:alpine | alpine | 160 MB | 23 s | — |
| spaceship:bookworm-numpy | bookworm | 1690 MB | 175 s | — |
| spaceship:alpine-numpy | alpine | 297 MB | 46 s | — |

### Що робив

**v1/v2** — неоптимальний Dockerfile: `COPY . .` і `RUN pip install` в одному кроці. При зміні будь-якого файлу кеш залежностей інвалідується, pip встановлює все заново.

**v3** — розділив на два кроки: спочатку `COPY requirements.txt` + `RUN pip install`, потім `COPY . .`. Після зміни коду кеш залежностей зберігається — збірка займає секунди.

**alpine** — замінив `python:3.13-bookworm` на `python:3.13-alpine`. Розмір впав з 1570 MB до 160 MB (в 10 разів).

**numpy** — додав залежність і ендпоінт `/matrix` який генерує дві матриці 10x10 і множить їх. На alpine numpy компілюється з вихідників (немає готових wheels для musl), тому збірка довша ніж на bookworm, але фінальний образ все одно менший.

### Висновки
Порядок шарів — найпростіша оптимізація з найбільшим ефектом. Alpine дає образи в 5-10 разів менші, але для пакетів з C-розширеннями (numpy) збірка довша через відсутність prebuilt wheels.

---

## 1.2 Musl (Alpine) vs glibc (Debian)

### Що робив

Запустив DNS сервер dnsmasq з кастомним доменом `myservice.internal.corp → 10.0.0.50` і прапором `--dns-search=corp`. Потім перевірив резолвінг `myservice.internal` з ubuntu і alpine контейнерів.

### Результати з логів DNS сервера

**Ubuntu (glibc):** спочатку запитав `myservice.internal` → NXDOMAIN, потім автоматично додав суфікс і запитав `myservice.internal.corp` → **10.0.0.50 ✅**

**Alpine (musl):** запитав `myservice.internal` → NXDOMAIN ❌. Суфікс не додав, більше не намагався.

### Висновок
musl не підтримує DNS search domains так само як glibc. У Kubernetes де сервіси резолвляться через `svc.cluster.local`, Alpine-контейнери можуть не знаходити інші сервіси по короткому імені. Рішення — використовувати повні FQDN.

---

## 1.3 Golang + Multi-stage builds

Проект: https://github.com/comsys-kpi-ua/deploy.lab-containers-starter-project-golang

### Результати

| Образ | Тип | Розмір | Час збірки |
|-------|-----|--------|------------|
| goapp:v1 | Звичайний (golang:1.22) | 1330 MB | 165 s |
| goapp:scratch | Multi-stage + scratch | 16.7 MB | 125 s |
| goapp:distroless | Multi-stage + distroless | 22.9 MB | 190 s |

### Що робив

**v1** — звичайний образ на базі `golang:1.22`. Містить весь toolchain, вихідники, кеш модулів — все непотрібне для запуску.

**scratch** — multi-stage: на першому етапі збираємо бінарник (`CGO_ENABLED=0`), на другому копіюємо тільки його у `FROM scratch`. Розмір впав з 1330 MB до 16.7 MB — у **80 разів**. Мінус: немає shell, неможливо зайти в контейнер для діагностики.

**distroless** — те саме але замість scratch використав `gcr.io/distroless/static-debian12`. Трохи більший (22.9 MB), зате містить CA сертифікати і підтримує non-root користувача.

### Висновок
Multi-stage build обов'язковий для компільованих мов. scratch — для максимального мінімалізму, distroless — для балансу між розміром і безпекою.

---

## 2. Практична частина — Docker Compose

Репозиторій: https://github.com/mykhailosoloma/mywebapp-lab1

Автоматизував запуск трьох сервісів з лаб.1: PostgreSQL, Spring Boot, Nginx.

**Файли:** `Dockerfile`, `docker-compose.yml`, `deploy/nginx-mywebapp.conf`

**Запуск:**
```bash
git clone https://github.com/mykhailosoloma/mywebapp-lab1
cd mywebapp-lab1
docker compose up -d --build
```

### Ключові рішення

- Окрема мережа `backend` — сервіси ізольовані, назовні відкритий тільки порт 80 (nginx)
- Named volume `postgres_data` — дані БД переживають перезапуск і перезавантаження системи
- `migration.sql` монтується в `docker-entrypoint-initdb.d/` — виконується автоматично при першому старті
- `depends_on` з `condition: service_healthy` — app стартує після готовності БД, nginx — після готовності app
- Dockerfile для Spring Boot — multi-stage: maven у builder, тільки jar у фінальному образі на базі `eclipse-temurin:21-jre-alpine`

### Перевірка
```bash
docker compose ps
curl http://localhost/tasks
```

---

## Загальні рекомендації

1. Завжди розділяти залежності і код на окремі шари — залежності вище, код нижче
2. Використовувати alpine для зменшення розміру, але враховувати musl обмеження
3. Multi-stage build обов'язковий для компільованих мов
4. Healthcheck + depends_on для правильного порядку старту сервісів
5. Named volumes для даних БД — ніколи bind mounts