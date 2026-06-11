#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CONFIG_FILE="/etc/mita/server_config.json"
SCRIPT_URL="https://raw.githubusercontent.com/gkzgtzfv49-spec/Mieru-Script/main/mieru.sh"

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Запускай от root: sudo bash $0${NC}"
  exit 1
fi

# сохраняем себя на диск
if [[ ! -f "/root/mieru-setup.sh" ]]; then
  curl -sSL "$SCRIPT_URL" -o /root/mieru.sh
  chmod +x /root/mieru.sh
fi
if [[ ! -f "/usr/local/bin/mieru-manage" ]]; then
  ln -sf /root/mieru.sh /usr/local/bin/mieru-manage
  chmod +x /usr/local/bin/mieru-manage 2>/dev/null || true
fi

# ══════════════════════════════════════════════════
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ══════════════════════════════════════════════════

get_latest_version() {
  curl -sSL "https://api.github.com/repos/enfein/mieru/releases/latest" \
    | grep '"tag_name"' | head -1 | grep -oP 'v[\d.]+' || echo "v3.33.0"
}

get_server_ip() {
  local IP=""
  for SVC in "ifconfig.me" "api.ipify.org" "ipecho.net/plain" "icanhazip.com"; do
    IP=$(curl -s --max-time 5 "$SVC" 2>/dev/null | tr -d '[:space:]')
    [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
    IP=""
  done
  [[ -z "$IP" ]] && read -rp "  Введи IP сервера вручную: " IP
  echo "$IP"
}

count_users() {
  [[ ! -f "$CONFIG_FILE" ]] && echo "0" && return
  python3 -c "
import json
with open('$CONFIG_FILE') as f: c=json.load(f)
print(len(c.get('users',[])))
" 2>/dev/null || echo "0"
}

list_users() {
  [[ ! -f "$CONFIG_FILE" ]] && echo "  Нет пользователей" && return
  python3 -c "
import json
with open('$CONFIG_FILE') as f: c=json.load(f)
users = c.get('users',[])
for i,u in enumerate(users):
    print(f\"{i+1}. {u['name']}\")
" 2>/dev/null
}

get_ports() {
  [[ ! -f "$CONFIG_FILE" ]] && echo "—" && return
  python3 -c "
import json
with open('$CONFIG_FILE') as f: c=json.load(f)
ports = []
for pb in c.get('portBindings',[]):
    if 'port' in pb:
        ports.append(str(pb['port']))
    elif 'portRange' in pb:
        ports.append(pb['portRange'])
print(', '.join(ports) if ports else '—')
" 2>/dev/null || echo "—"
}

restart_mita() {
  mita stop 2>/dev/null || true
  sleep 1
  mita start
  sleep 1
  STATUS=$(mita status 2>/dev/null || echo "unknown")
  if echo "$STATUS" | grep -qi "RUNNING"; then
    echo -e "  ✓ ${GREEN}mita запущен${NC}"
  else
    echo -e "  ${RED}mita не запустился!${NC}"
    echo "  $STATUS"
  fi
}

# ══════════════════════════════════════════════════
# УСТАНОВКА
# ══════════════════════════════════════════════════
install_mieru() {
  clear
  echo -e "${CYAN}"
  echo "╔════════════════════════════════════════════╗"
  echo "║         mieru — Установка с нуля           ║"
  echo "╚════════════════════════════════════════════╝"
  echo -e "${NC}"

  echo -e "${YELLOW}[1/5] Подготовка системы...${NC}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq curl wget python3 ufw ntp qrencode
  timedatectl set-ntp true 2>/dev/null || true
  echo -e "  ✓ Готово"

  echo -e "${YELLOW}[2/5] Получаю последнюю версию mieru...${NC}"
  VERSION=$(get_latest_version)
  echo -e "  Версия: ${GREEN}$VERSION${NC}"
  VER="${VERSION#v}"

  ARCH=$(uname -m)
  if [[ "$ARCH" == "x86_64" ]]; then
    DEB_URL="https://github.com/enfein/mieru/releases/download/${VERSION}/mita_${VER}_amd64.deb"
  elif [[ "$ARCH" == "aarch64" ]]; then
    DEB_URL="https://github.com/enfein/mieru/releases/download/${VERSION}/mita_${VER}_arm64.deb"
  else
    echo -e "  ${RED}Неподдерживаемая архитектура: $ARCH${NC}"; exit 1
  fi

  echo -e "${YELLOW}[3/5] Устанавливаю mita...${NC}"
  if command -v mita &>/dev/null; then
    echo -e "  mita уже установлен: $(mita version 2>/dev/null | head -1)"
  else
    curl -sSLO "$DEB_URL"
    dpkg -i "mita_${VER}_amd64.deb" 2>/dev/null || dpkg -i "mita_${VER}_arm64.deb" 2>/dev/null || true
    rm -f "mita_${VER}_amd64.deb" "mita_${VER}_arm64.deb" 2>/dev/null || true
    usermod -a -G mita root 2>/dev/null || true
    echo -e "  ✓ mita установлен"
  fi

  echo -e "${YELLOW}[4/5] Настройка...${NC}"
  setup_config

  echo -e "${YELLOW}[5/5] UFW...${NC}"
  ufw --force reset >/dev/null 2>&1
  ufw default deny incoming >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  ufw allow 22/tcp >/dev/null 2>&1

  # открываем порты из конфига
  python3 -c "
import json
with open('$CONFIG_FILE') as f: c=json.load(f)
import subprocess
for pb in c.get('portBindings',[]):
    proto = pb.get('protocol','TCP').lower()
    if 'port' in pb:
        subprocess.run(['ufw','allow',f\"{pb['port']}/{proto}\"], capture_output=True)
    elif 'portRange' in pb:
        r = pb['portRange']
        subprocess.run(['ufw','allow',f\"{r}/{proto}\"], capture_output=True)
" 2>/dev/null || true

  ufw --force enable >/dev/null 2>&1
  echo -e "  ✓ Порты открыты"

  ln -sf /root/mieru.sh /usr/local/bin/mieru-manage 2>/dev/null || true
  chmod +x /usr/local/bin/mieru-manage 2>/dev/null || true

  echo ""
  echo -e "${GREEN}  Установка завершена!${NC}"
  echo -e "${GREEN}  Для управления: ${CYAN}mieru-manage${NC}"
  echo ""
  read -rp "  Enter..." _
}

# ══════════════════════════════════════════════════
# НАСТРОЙКА КОНФИГА
# ══════════════════════════════════════════════════
setup_config() {
  echo ""
  echo -e "${BOLD}  Настройка сервера:${NC}"
  echo ""

  # порт
  read -rp "  Порт (1025-65535) [2080]: " PORT
  PORT=${PORT:-2080}
  if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1025 ]] || [[ "$PORT" -gt 65535 ]]; then
    echo -e "  ${RED}Неверный порт, ставлю 2080${NC}"; PORT=2080
  fi

  # протокол
  echo ""
  echo -e "  Протокол транспорта:"
  echo -e "  1. TCP  (стабильный, обходит большинство блокировок)"
  echo -e "  2. UDP  (быстрее, использует BBR)"
  read -rp "  Выбор [1]: " PROTO_CHOICE
  PROTO_CHOICE=${PROTO_CHOICE:-1}
  [[ "$PROTO_CHOICE" == "2" ]] && PROTO="UDP" || PROTO="TCP"

  # пользователи
  echo ""
  echo -e "${BOLD}  Добавь пользователей:${NC}"
  echo ""
  read -rp "  Сколько создать? [1]: " CNT; CNT=${CNT:-1}
  [[ ! "$CNT" =~ ^[0-9]+$ ]] && CNT=1

  USERS_JSON=""
  for ((i=1; i<=CNT; i++)); do
    echo ""
    echo -e "  ${BOLD}Пользователь $i:${NC}"
    read -rp "  Имя: " UNAME
    [[ -z "$UNAME" ]] && UNAME="user$i"
    read -rp "  Пароль (Enter=авто): " UPASS
    [[ -z "$UPASS" ]] && UPASS=$(openssl rand -hex 16) && echo -e "  Авто: ${GREEN}$UPASS${NC}"
    [[ -n "$USERS_JSON" ]] && USERS_JSON+=","
    USERS_JSON+="{\"name\":\"$UNAME\",\"password\":\"$UPASS\"}"
  done

  # записываем конфиг
  mkdir -p /etc/mita
  cat > "$CONFIG_FILE" << EOF
{
  "portBindings": [
    {
      "port": $PORT,
      "protocol": "$PROTO"
    }
  ],
  "users": [$USERS_JSON],
  "loggingLevel": "INFO",
  "mtu": 1400
}
EOF

  mita apply config "$CONFIG_FILE"
  echo ""
  echo -e "  ✓ Конфиг применён"

  restart_mita
  show_client_config
}

# ══════════════════════════════════════════════════
# ПОКАЗАТЬ КОНФИГ ДЛЯ КЛИЕНТА
# ══════════════════════════════════════════════════
rm -f /tmp/mieru_show.py
cat > /tmp/mieru_show.py << 'PYEOF'
import json, sys, base64, struct

config_file = sys.argv[1]
server_ip   = sys.argv[2]

with open(config_file) as f:
    c = json.load(f)

port_bindings = c.get('portBindings', [])
users = c.get('users', [])

# берём первый порт
first_port = 443
first_proto = 'TCP'
for pb in port_bindings:
    if 'port' in pb:
        first_port = pb['port']
        first_proto = pb.get('protocol', 'TCP')
        break

def make_nekobox_link(server_ip, port, proto, username, password):
    # sn://mieru?<base64(protobuf)>
    # упрощённая версия — mieru URI format
    import urllib.parse
    params = {
        'server': server_ip,
        'port': str(port),
        'transport': proto,
        'username': username,
        'password': password,
        'multiplexing': 'MULTIPLEXING_HIGH'
    }
    query = urllib.parse.urlencode(params)
    return 'mieru://' + server_ip + ':' + str(port) + '?' + query + '#' + urllib.parse.quote(username)

print('')
print('  ' + '='*50)
print('  Конфиги для клиентов mieru:')
print('  ' + '='*50)

for user in users:
    client_ports = []
    for pb in port_bindings:
        proto = pb.get('protocol', 'TCP')
        p_proto = 'TCP_PROXY_PROTOCOL' if proto == 'TCP' else 'UDP_PROXY_PROTOCOL'
        if 'port' in pb:
            client_ports.append({'port': pb['port'], 'protocol': p_proto})
        elif 'portRange' in pb:
            client_ports.append({'portRange': pb['portRange'], 'protocol': p_proto})

    client_cfg = {
        'profile': [{
            'ipAddress': server_ip,
            'portBindings': client_ports,
            'user': [{'name': user['name'], 'password': user['password']}]
        }]
    }

    print('')
    print('  Пользователь: ' + user['name'])
    print('  Пароль:       ' + user['password'])
    print('')

    # mieru / NekoBox / Karing URI
    nekobox = make_nekobox_link(server_ip, first_port, first_proto, user['name'], user['password'])
    print('  ── Karing / NekoBox (URI) ──')
    print('  ' + nekobox)
    print('')

    # Clash / Karing YAML
    clash_lines = [
        'proxies:',
        '  - name: ' + user['name'],
        '    type: mieru',
        '    server: ' + server_ip,
        '    port: ' + str(first_port),
        '    transport: ' + first_proto,
        '    udp: true',
        '    username: ' + user['name'],
        '    password: ' + user['password'],
        '    multiplexing: MULTIPLEXING_HIGH',
    ]
    print('  -- Clash / Karing (YAML) --')
    for line in clash_lines:
        print('  ' + line)
    print('')

    # mieru нативный JSON
    print('  ── mieru нативный (client_config.json) ──')
    print(json.dumps(client_cfg, indent=2, ensure_ascii=False))
    print('  ' + '-'*38)
PYEOF

show_client_config() {
  [[ ! -f "$CONFIG_FILE" ]] && echo -e "  ${RED}Конфиг не найден${NC}" && return
  local SERVER_IP
  SERVER_IP=$(get_server_ip)

  # устанавливаем qrencode если нет
  command -v qrencode &>/dev/null || apt-get install -y -qq qrencode

  # генерируем конфиги через python
  python3 - "$CONFIG_FILE" "$SERVER_IP" << 'PYEOF' > /tmp/mieru_output.txt
import json, sys

config_file = sys.argv[1]
server_ip   = sys.argv[2]

with open(config_file) as f:
    c = json.load(f)

port_bindings = c.get('portBindings', [])
users = c.get('users', [])

first_port = 443
first_proto = 'TCP'
for pb in port_bindings:
    if 'port' in pb:
        first_port = pb['port']
        first_proto = pb.get('protocol', 'TCP')
        break

print('')
print('  ' + '='*50)
print('  Конфиги для клиентов mieru:')
print('  ' + '='*50)

for user in users:
    client_ports = []
    for pb in port_bindings:
        proto = pb.get('protocol', 'TCP')
        p_proto = 'TCP_PROXY_PROTOCOL' if proto == 'TCP' else 'UDP_PROXY_PROTOCOL'
        if 'port' in pb:
            client_ports.append({'port': pb['port'], 'protocol': p_proto})
        elif 'portRange' in pb:
            client_ports.append({'portRange': pb['portRange'], 'protocol': p_proto})

    client_cfg = {'profile': [{'ipAddress': server_ip, 'portBindings': client_ports,
        'user': [{'name': user['name'], 'password': user['password']}]}]}

    sep = '=' * 52
    dash = '-' * 52

    print('')
    print('  ' + sep)
    print('  👤 Пользователь: ' + user['name'])
    print('  🔑 Пароль:       ' + user['password'])
    print('  ' + sep)

    print('')
    print('  >>> Clash / Karing — скопируй в конфиг YAML <<<')
    clash_lines = ['proxies:',
        '  - name: ' + user['name'], '    type: mieru',
        '    server: ' + server_ip, '    port: ' + str(first_port),
        '    transport: ' + first_proto, '    udp: true',
        '    username: ' + user['name'], '    password: ' + user['password'],
        '    multiplexing: MULTIPLEXING_HIGH']
    for line in clash_lines:
        print('  ' + line)

    print('')
    print('  >>> mieru нативный — сохрани как client_config.json <<<')
    print(json.dumps(client_cfg, indent=2, ensure_ascii=False))
    print('  ' + dash)
PYEOF

  cat /tmp/mieru_output.txt

  echo ""

}


# ══════════════════════════════════════════════════
# ДОБАВИТЬ ПОЛЬЗОВАТЕЛЯ
# ══════════════════════════════════════════════════
add_user() {
  echo ""
  read -rp "  Имя пользователя: " UNAME
  [[ -z "$UNAME" ]] && { echo -e "  ${RED}Имя не может быть пустым!${NC}"; return; }
  read -rp "  Пароль (Enter=авто): " UPASS
  [[ -z "$UPASS" ]] && UPASS=$(openssl rand -hex 16) && echo -e "  Авто: ${GREEN}$UPASS${NC}"

  python3 -c "
import json
with open('$CONFIG_FILE') as f: c=json.load(f)
for u in c.get('users',[]):
    if u['name'] == '$UNAME':
        print('EXISTS'); exit()
c.setdefault('users',[]).append({'name':'$UNAME','password':'$UPASS'})
with open('$CONFIG_FILE','w') as f: json.dump(c,f,indent=2)
print('OK')
" | grep -q "EXISTS" && { echo -e "  ${RED}Пользователь уже существует!${NC}"; return; }

  mita apply config "$CONFIG_FILE"
  mita reload 2>/dev/null || restart_mita
  echo -e "  ✓ ${GREEN}Пользователь $UNAME добавлен${NC}"
}

# ══════════════════════════════════════════════════
# УДАЛИТЬ ПОЛЬЗОВАТЕЛЯ
# ══════════════════════════════════════════════════
remove_user() {
  echo ""
  echo -e "${BOLD}  Пользователи:${NC}"
  list_users
  echo ""
  read -rp "  Номер для удаления: " NUM
  RESULT=$(python3 -c "
import json
with open('$CONFIG_FILE') as f: c=json.load(f)
users = c.get('users',[])
idx = int('$NUM') - 1
if idx < 0 or idx >= len(users): print('ERROR'); exit()
removed = users.pop(idx)
c['users'] = users
with open('$CONFIG_FILE','w') as f: json.dump(c,f,indent=2)
print(removed['name'])
" 2>/dev/null)
  [[ "$RESULT" == "ERROR" ]] && { echo -e "  ${RED}Неверный номер!${NC}"; return; }
  mita apply config "$CONFIG_FILE"
  mita reload 2>/dev/null || restart_mita
  echo -e "  ✓ ${GREEN}Удалён: $RESULT${NC}"
}

# ══════════════════════════════════════════════════
# МЕНЮ
# ══════════════════════════════════════════════════
show_one_user() {
  [[ ! -f "$CONFIG_FILE" ]] && echo -e "  ${RED}Конфиг не найден${NC}" && return
  local SERVER_IP
  SERVER_IP=$(get_server_ip)

  echo ""
  echo -e "${BOLD}  Пользователи:${NC}"
  list_users
  echo ""
  read -rp "  Номер пользователя: " NUM

  command -v qrencode &>/dev/null || apt-get install -y -qq qrencode

  python3 - "$CONFIG_FILE" "$SERVER_IP" "$NUM" << 'PYEOF' > /tmp/mieru_one.txt
import json, sys

config_file = sys.argv[1]
server_ip   = sys.argv[2]
num         = int(sys.argv[3]) - 1

with open(config_file) as f:
    c = json.load(f)

port_bindings = c.get('portBindings', [])
users = c.get('users', [])

if num < 0 or num >= len(users):
    print('ERROR'); sys.exit(1)

user = users[num]

first_port = 443
first_proto = 'TCP'
for pb in port_bindings:
    if 'port' in pb:
        first_port = pb['port']
        first_proto = pb.get('protocol', 'TCP')
        break

client_ports = []
for pb in port_bindings:
    proto = pb.get('protocol', 'TCP')
    p_proto = 'TCP_PROXY_PROTOCOL' if proto == 'TCP' else 'UDP_PROXY_PROTOCOL'
    if 'port' in pb:
        client_ports.append({'port': pb['port'], 'protocol': p_proto})
    elif 'portRange' in pb:
        client_ports.append({'portRange': pb['portRange'], 'protocol': p_proto})

client_cfg = {'profile': [{'ipAddress': server_ip, 'portBindings': client_ports,
    'user': [{'name': user['name'], 'password': user['password']}]}]}

sep = '=' * 52
dash = '-' * 52

print('')
print('  ' + sep)
print('  Пользователь: ' + user['name'])
print('  Пароль:       ' + user['password'])
print('  ' + sep)

print('')
print('  >>> Clash / Karing — скопируй в конфиг YAML <<<')
clash_lines = ['proxies:',
    '  - name: ' + user['name'], '    type: mieru',
    '    server: ' + server_ip, '    port: ' + str(first_port),
    '    transport: ' + first_proto, '    udp: true',
    '    username: ' + user['name'], '    password: ' + user['password'],
    '    multiplexing: MULTIPLEXING_HIGH']
for line in clash_lines:
    print('  ' + line)

print('')
print('  >>> mieru нативный — сохрани как client_config.json <<<')
print(json.dumps(client_cfg, indent=2, ensure_ascii=False))
print('  ' + dash)
PYEOF

  if grep -q "ERROR" /tmp/mieru_one.txt 2>/dev/null; then
    echo -e "  ${RED}Неверный номер!${NC}"
    return
  fi

  cat /tmp/mieru_one.txt
  echo ""
}

menu() {
  set +e
  while true; do
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════╗"
    echo "║         mieru — Панель управления          ║"
    echo "╚════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  Порты:         ${GREEN}$(get_ports)${NC}"
    echo -e "  Пользователей: ${GREEN}$(count_users)${NC}"
    echo -e "  Статус mita:   ${GREEN}$(mita status 2>/dev/null | grep -oP 'RUNNING|IDLE|STOPPED' || echo 'неизвестно')${NC}"
    echo ""
    echo -e "  ${BOLD}── Пользователи ──${NC}"
    echo -e "  ${BOLD}1.${NC} Показать всех"
    echo -e "  ${BOLD}2.${NC} Добавить пользователя"
    echo -e "  ${BOLD}3.${NC} Удалить пользователя"
    echo -e "  ${BOLD}4.${NC} Показать конфиг одного пользователя"
    echo -e "  ${BOLD}5.${NC} Показать конфиги всех пользователей"
    echo ""
    echo -e "  ${BOLD}── Сервер ──${NC}"
    echo -e "  ${BOLD}6.${NC} Перенастроить (сменить порт/протокол)"
    echo -e "  ${BOLD}7.${NC} Перезапустить mita"
    echo -e "  ${BOLD}8.${NC} Статус и логи"
    echo -e "  ${BOLD}9.${NC} Обновить скрипт"
    echo -e "  ${BOLD}0.${NC} Выйти"
    echo ""
    read -rp "  Выбор: " CHOICE

    case $CHOICE in
      1) echo ""; list_users; echo ""; read -rp "  Enter..." _ ;;
      2) add_user; echo ""; read -rp "  Enter..." _ ;;
      3) remove_user; echo ""; read -rp "  Enter..." _ ;;
      4) show_one_user; echo ""; read -rp "  Enter..." _ ;;
      5) show_client_config; read -rp "  Enter..." _ ;;
      6) setup_config; echo ""; read -rp "  Enter..." _ ;;
      7) restart_mita; echo ""; read -rp "  Enter..." _ ;;
      8)
        echo ""
        systemctl status mita --no-pager
        echo ""
        journalctl -u mita -n 20 --no-pager
        echo ""
        read -rp "  Enter..." _
        ;;
      9)
        curl -sSL "$SCRIPT_URL" -o /root/mieru.sh
        chmod +x /root/mieru.sh
        echo -e "  ${GREEN}✓ Скрипт обновлён${NC}"
        sleep 1
        exec bash /root/mieru.sh
        ;;
      0) echo "Выход."; exit 0 ;;
      *) echo -e "  ${RED}Неверный выбор${NC}"; sleep 1 ;;
    esac
  done
}

# ══════════════════════════════════════════════════
# ТОЧКА ВХОДА
# ══════════════════════════════════════════════════
if command -v mita &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
  menu
  exit 0
fi

install_mieru
