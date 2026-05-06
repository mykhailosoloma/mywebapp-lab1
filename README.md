# mywebapp — Task Tracker

## Варіант

| Параметр | Значення |
|---|---|
| N (номер у списку групи) | 25 |
| V2 = (25 % 2) + 1 | **2** → Конфіг-файл, PostgreSQL |
| V3 = (25 % 3) + 1 | **2** → Task Tracker |
| V5 = (25 % 5) + 1 | **1** → Порт 8080 |

**Застосунок:** Task Tracker  
**База даних:** PostgreSQL  
**Конфігурація:** файл `/etc/mywebapp/config.yml`  
**Порт застосунку:** `127.0.0.1:8080`  
**Nginx:** `0.0.0.0:80` → reverse proxy

---

## Архітектура

```
client → nginx (:80) → mywebapp (:8080, 127.0.0.1) → PostgreSQL (:5432, 127.0.0.1)
```

---

## API

| Метод | Ендпоінт | Опис |
|---|---|---|
| GET | `/` | HTML-сторінка зі списком ендпоінтів (тільки text/html) |
| GET | `/tasks` | Список задач (JSON або HTML залежно від `Accept`) |
| POST | `/tasks` | Створити задачу (body: `{"title": "..."}`) |
| POST | `/tasks/{id}/done` | Позначити задачу як виконану |
| GET | `/health/alive` | Перевірка живості (завжди 200 OK) |
| GET | `/health/ready` | Перевірка готовності (200 якщо БД доступна) |

> `/health/*` не доступні через nginx (тільки внутрішньо)

### Приклади

```bash
# Список задач (JSON)
curl -H "Accept: application/json" http://localhost/tasks

# Список задач (HTML)
curl -H "Accept: text/html" http://localhost/tasks

# Створити задачу
curl -X POST -H "Content-Type: application/json" \
     -d '{"title":"Написати лабораторну"}' \
     http://localhost/tasks

# Позначити задачу 1 як виконану
curl -X POST http://localhost/tasks/1/done
```

### Формат відповіді (JSON)

```json
{
  "id": 1,
  "title": "Написати лабораторну",
  "status": "pending",
  "created_at": "2024-05-01 12:00:00"
}
```

---

## Конфігураційний файл

Шлях: `/etc/mywebapp/config.yml`

```yaml
app:
  server:
    host: 127.0.0.1
    port: 8080
  database:
    host: 127.0.0.1
    port: 5432
    name: mywebapp
    user: mywebapp
    password: YOUR_PASSWORD
```

---

## Середовище розробки

**Вимоги:** Java 21, Maven 3.9+, PostgreSQL 14+

```bash
# Клонування
git clone https://github.com/YOURUSER/mywebapp.git
cd mywebapp

# Запустити PostgreSQL локально і створити БД
sudo -u postgres psql -c "CREATE USER mywebapp PASSWORD 'mywebapp';"
sudo -u postgres psql -c "CREATE DATABASE mywebapp OWNER mywebapp;"

# Міграція
psql -h 127.0.0.1 -U mywebapp -d mywebapp -f src/main/resources/migration.sql

# Скопіювати конфіг
sudo mkdir -p /etc/mywebapp
sudo cp config.yml.example /etc/mywebapp/config.yml

# Збірка і запуск
./mvnw package -DskipTests
java -jar target/mywebapp.jar
```

---

## Розгортання на VM

### Образ VM

- **Дистрибутив:** Ubuntu 24.04 LTS Server (офіційний образ)
- **Завантажити:** https://ubuntu.com/download/server
- **Рекомендований образ:** `ubuntu-24.04-live-server-amd64.iso`

### Вимоги до ресурсів

| Ресурс | Мінімум |
|---|---|
| CPU | 1 vCPU |
| RAM | 1 GB |
| Disk | 10 GB |

### Спеціальні налаштування при встановленні OS

Спеціальних налаштувань не потрібно. При встановленні Ubuntu Server:
- Розбивка диску: стандартна (весь диск одним розділом)
- Під час інсталятора буде запропоновано створити користувача — можна назвати `ubuntu` (він буде заблокований скриптом після розгортання)
- Увімкнути OpenSSH Server при встановленні

### Вхід на VM

**SSH (рекомендовано):**
```bash
ssh ubuntu@<VM_IP>
```

| Параметр | Значення |
|---|---|
| Користувач | `ubuntu` (дефолтний, створюється інсталятором) |
| Пароль | задається під час встановлення Ubuntu |
| Порт | 22 |

> Після виконання скрипта `deploy.sh` дефолтний користувач `ubuntu` буде заблокований. Надалі входити через `student` або `teacher` (пароль `12345678`, потрібно змінити при першому вході).

### Користувачі після розгортання

| Користувач | Пароль за замовч. | Права |
|---|---|---|
| student | 12345678 (змінити при першому вході) | sudo |
| teacher | 12345678 (змінити при першому вході) | sudo |
| mywebapp | — (системний, без логіну) | мінімальні |
| operator | 12345678 (змінити при першому вході) | лише управління mywebapp + reload nginx |

### Автоматичне розгортання

```bash
# 1. Зібрати jar локально (потрібен Java 21 + Maven)
./mvnw package -DskipTests

# 2. Скопіювати необхідні файли на VM
scp target/mywebapp.jar                      ubuntu@<VM_IP>:/tmp/
scp src/main/resources/migration.sql         ubuntu@<VM_IP>:/tmp/
scp src/main/resources/migrate.sh            ubuntu@<VM_IP>:/tmp/
scp deploy/deploy.sh                         ubuntu@<VM_IP>:/tmp/

# 3. Підключитись на VM і запустити скрипт
ssh ubuntu@<VM_IP>
cd /tmp
chmod +x deploy.sh migrate.sh
sudo ./deploy.sh
```

> Скрипт встановить всі пакети, створить користувачів, налаштує PostgreSQL, розгорне застосунок, налаштує nginx і заблокує дефолтного користувача `ubuntu`.

---

## Тестування

```bash
# --- Перевірка health (тільки з середини VM, не через nginx) ---
curl http://127.0.0.1:8080/health/alive   # → 200 OK
curl http://127.0.0.1:8080/health/ready   # → 200 OK (якщо БД доступна)

# --- Через nginx (зовні) ---

# Кореневий ендпоінт (HTML)
curl -H "Accept: text/html" http://<VM_IP>/

# Список задач — JSON
curl -H "Accept: application/json" http://<VM_IP>/tasks

# Список задач — HTML
curl -H "Accept: text/html" http://<VM_IP>/tasks

# Створити задачу
curl -X POST -H "Content-Type: application/json" \
     -d '{"title":"Test task"}' http://<VM_IP>/tasks

# Позначити задачу як виконану
curl -X POST http://<VM_IP>/tasks/1/done

# Health через nginx — має повернути 404 (не проксується)
curl -v http://<VM_IP>/health/alive

# --- Системні перевірки ---

# Статус сервісу
sudo systemctl status mywebapp
sudo systemctl status mywebapp.socket
journalctl -u mywebapp -f

# Логи nginx
tail -f /var/log/nginx/mywebapp_access.log

# Перевірка прав operator
su - operator
sudo systemctl status mywebapp    # OK
sudo systemctl restart mywebapp   # OK
sudo systemctl reload nginx       # OK
sudo systemctl status nginx       # має видати помилку (не дозволено)
```

---

## systemd

Файли:
- `/etc/systemd/system/mywebapp.service` — основний сервіс
- `/etc/systemd/system/mywebapp.socket` — socket activation

Сервіс запускається від системного користувача `mywebapp`, виконує міграцію БД перед стартом через `ExecStartPre`.