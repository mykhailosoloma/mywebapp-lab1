# mywebapp — Task Tracker

## Варіант

| Параметр | Формула | Результат |
|---|---|---|
| N (номер у списку групи) | — | **25** |
| V2 | (25 % 2) + 1 | **2** → Конфіг-файл `/etc/mywebapp/config.yml`, PostgreSQL |
| V3 | (25 % 3) + 1 | **2** → Task Tracker |
| V5 | (25 % 5) + 1 | **1** → Порт 8080 |

## Опис застосунку

Task Tracker — веб-сервіс для відстеження задач. Дозволяє створювати задачі, переглядати список і позначати їх як виконані.

## Архітектура

```
client → nginx (0.0.0.0:80) → mywebapp (127.0.0.1:8080) → PostgreSQL (127.0.0.1:5432)
```

- **nginx** — reverse proxy, слухає на порту 80, проксує тільки бізнес-ендпоінти
- **mywebapp** — Spring Boot застосунок, слухає тільки на localhost:8080
- **PostgreSQL** — база даних, доступна тільки з localhost
- **Systemd socket activation** — `mywebapp.socket` тримає порт 8080, при першому з'єднанні автоматично запускає `mywebapp.service`

---

## API

| Метод | Ендпоінт | Опис |
|---|---|---|
| GET | `/` | Список всіх ендпоінтів (тільки `text/html`) |
| GET | `/tasks` | Список задач (`application/json` або `text/html`) |
| POST | `/tasks` | Створити задачу (body: `{"title": "..."}`) |
| POST | `/tasks/{id}/done` | Позначити задачу як виконану |
| GET | `/health/alive` | Перевірка живості — завжди 200 OK |
| GET | `/health/ready` | Перевірка готовності — 200 якщо БД доступна |

> `/health/*` не проксуються через nginx — доступні тільки з самої VM

### Поведінка залежно від Accept header

- `Accept: application/json` → JSON-відповідь
- `Accept: text/html` → HTML-сторінка з таблицею

### Приклади запитів

```bash
# Кореневий ендпоінт
curl -H "Accept: text/html" http://localhost/

# Список задач — JSON
curl -H "Accept: application/json" http://localhost/tasks

# Список задач — HTML
curl -H "Accept: text/html" http://localhost/tasks

# Створити задачу
curl -X POST \
     -H "Content-Type: application/json" \
     -d '{"title": "Написати лабораторну"}' \
     http://localhost/tasks

# Позначити задачу 1 як виконану
curl -X POST http://localhost/tasks/1/done
```

### Формат JSON

```json
{
  "id": 1,
  "title": "Написати лабораторну",
  "status": "pending",
  "created_at": "2024-05-01 12:00:00"
}
```

Поле `status` може бути `"pending"` або `"done"`.

---

## Конфігурація

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

Приклад файлу: [`deploy/config.yml.example`](deploy/config.yml.example)

---

## Середовище розробки

**Вимоги:** Java 21, Maven 3.9+, PostgreSQL 14+

```bash
git clone https://github.com/YOURUSER/mywebapp-lab1.git
cd mywebapp-lab1

# Створити БД
sudo -u postgres psql -c "CREATE USER mywebapp PASSWORD 'mywebapp';"
sudo -u postgres psql -c "CREATE DATABASE mywebapp OWNER mywebapp;"

# Налаштувати конфіг
sudo mkdir -p /etc/mywebapp
sudo cp deploy/config.yml.example /etc/mywebapp/config.yml
sudo nano /etc/mywebapp/config.yml  # встановити пароль

# Міграція БД
bash deploy/migrate.sh /etc/mywebapp/config.yml

# Збірка і запуск
cd mywebapp
./mvnw package -DskipTests
java -jar target/mywebapp.jar
```

---

## Розгортання на VM

### Образ VM

- **Дистрибутив:** Ubuntu 24.04 LTS Server (офіційний образ)
- **Завантажити:** https://ubuntu.com/download/server
- **Файл:** `ubuntu-24.04-live-server-amd64.iso`

### Вимоги до ресурсів

| Ресурс | Мінімум |
|---|---|
| CPU | 1 vCPU |
| RAM | 1 GB |
| Disk | 10 GB |

### Встановлення OS

Спеціальних налаштувань не потрібно. При встановленні:
- Розбивка диску: стандартна (весь диск)
- Створити користувача `ubuntu` (буде заблокований після розгортання)
- Увімкнути **OpenSSH Server**

### Крок 1 — Зібрати jar

На машині розробника (потрібен Java 21 + Maven):

```bash
cd mywebapp-lab1/mywebapp
./mvnw package -DskipTests
# Результат: target/mywebapp.jar
```

### Крок 2 — Скопіювати файли на VM

```bash
cd mywebapp-lab1

scp mywebapp/target/mywebapp.jar    ubuntu@<VM_IP>:/tmp/
scp deploy/migration.sql            ubuntu@<VM_IP>:/tmp/
scp deploy/migrate.sh               ubuntu@<VM_IP>:/tmp/
scp deploy/deploy.sh                ubuntu@<VM_IP>:/tmp/
scp deploy/mywebapp.service         ubuntu@<VM_IP>:/tmp/
scp deploy/mywebapp.socket          ubuntu@<VM_IP>:/tmp/
scp deploy/nginx-mywebapp.conf      ubuntu@<VM_IP>:/tmp/
```

### Крок 3 — Запустити скрипт

```bash
ssh ubuntu@<VM_IP>
cd /tmp
chmod +x deploy.sh migrate.sh
sudo bash deploy.sh
```

Скрипт автоматично:
1. Встановить пакети (Java, PostgreSQL, nginx)
2. Створить користувачів (student, teacher, operator, app)
3. Налаштує PostgreSQL і створить БД
4. Скопіює jar і конфігурацію
5. Встановить і запустить systemd socket + service
6. Налаштує nginx
7. Заблокує дефолтного користувача `ubuntu`

### Користувачі після розгортання

| Користувач | Пароль | Права |
|---|---|---|
| student | `12345678` ⚠️ змінити при першому вході | sudo (адмін) |
| teacher | `12345678` ⚠️ змінити при першому вході | sudo (адмін) |
| app | — (системний, без логіну) | мінімальні |
| operator | `12345678` ⚠️ змінити при першому вході | тільки управління mywebapp + reload nginx |

Вхід після розгортання:
```bash
ssh student@<VM_IP>
# або
ssh teacher@<VM_IP>
```

---

## Ручне тестування

### 1. Перевірка застосунку

```bash
# Health — напряму до застосунку (не через nginx)
curl http://127.0.0.1:8080/health/alive
# → OK

curl http://127.0.0.1:8080/health/ready
# → OK

# Health через nginx — має повернути 404
curl -v http://127.0.0.1/health/alive
# → HTTP/1.1 404
```

### 2. Перевірка API через nginx

```bash
# Кореневий ендпоінт
curl -H "Accept: text/html" http://127.0.0.1/
# → HTML сторінка зі списком ендпоінтів

# Порожній список задач
curl -H "Accept: application/json" http://127.0.0.1/tasks
# → []

# Створити задачу
curl -X POST \
     -H "Content-Type: application/json" \
     -d '{"title": "Перша задача"}' \
     http://127.0.0.1/tasks
# → {"id":1,"title":"Перша задача","status":"pending","created_at":"..."}

# Список задач у HTML
curl -H "Accept: text/html" http://127.0.0.1/tasks
# → HTML таблиця з задачею

# Позначити як виконану
curl -X POST http://127.0.0.1/tasks/1/done
# → {"id":1,...,"status":"done",...}

# Неіснуюча задача
curl -v -X POST http://127.0.0.1/tasks/999/done
# → HTTP/1.1 404

# Запит без title
curl -X POST \
     -H "Content-Type: application/json" \
     -d '{}' \
     http://127.0.0.1/tasks
# → {"error":"title is required"}
```

### 3. Перевірка systemd і socket activation

```bash
# Статус всіх сервісів
sudo systemctl status mywebapp.socket
sudo systemctl status mywebapp.service
sudo systemctl status nginx
sudo systemctl status postgresql

# Логи застосунку
journalctl -u mywebapp -n 50 --no-pager

# Тест socket activation:
# Зупиняємо сервіс — socket продовжує тримати порт
sudo systemctl stop mywebapp.service
sudo systemctl status mywebapp.socket    # active (listening) ← порт відкритий
sudo systemctl status mywebapp.service   # inactive (dead)
ss -tlnp | grep 8080                     # порт все ще слухає (systemd)

# Перший запит автоматично запускає сервіс
curl http://127.0.0.1/tasks
sudo systemctl status mywebapp.service   # active (running)
```

### 4. Перевірка мережевих обмежень

```bash
# PostgreSQL слухає тільки на localhost
ss -tlnp | grep 5432
# → 127.0.0.1:5432   (НЕ 0.0.0.0)

# Застосунок слухає тільки на localhost
ss -tlnp | grep 8080
# → 127.0.0.1:8080   (НЕ 0.0.0.0)

# Порт 8080 недоступний ззовні (тільки через nginx :80)
# Перевірити з іншої машини:
curl http://<VM_IP>:8080/tasks    # → connection refused
curl http://<VM_IP>/tasks         # → OK
```

### 5. Перевірка прав користувача operator

```bash
su - operator
# або ssh operator@<VM_IP>

# Ці команди мають ПРАЦЮВАТИ:
sudo systemctl status mywebapp    # OK
sudo systemctl stop mywebapp      # OK
sudo systemctl start mywebapp     # OK
sudo systemctl restart mywebapp   # OK
sudo systemctl reload nginx       # OK

# Ці команди мають ВІДМОВИТИ:
sudo systemctl status nginx        # → Sorry, user operator is not allowed...
sudo systemctl restart nginx       # → Sorry, user operator is not allowed...
sudo systemctl status postgresql   # → Sorry, user operator is not allowed...
sudo apt-get install nano          # → Sorry, user operator is not allowed...
sudo su -                          # → Sorry, user operator is not allowed...
```

### 6. Перевірка nginx логів

```bash
# Зробити кілька запитів і переглянути логи
curl http://127.0.0.1/tasks
curl http://127.0.0.1/tasks/1/done

tail /var/log/nginx/mywebapp_access.log
# → 127.0.0.1 - - [01/May/2024:12:00:00 +0000] "GET /tasks HTTP/1.1" 200 ...
```

### 7. Перевірка автозапуску після перезавантаження

```bash
sudo reboot

# Після перезавантаження:
ssh student@<VM_IP>
curl http://127.0.0.1/tasks
# → повинно відповісти без ручного запуску
```