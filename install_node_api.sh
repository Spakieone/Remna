#!/bin/bash

# Простой установщик Node API: всегда перезаписывает и перезапускает

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NODE_API_DIR="/home/node-manager/node-api"
NODE_API_SCRIPT="$NODE_API_DIR/node_api.py"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/node-api.service"
NODE_MANAGER_USER="node-manager"

log() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Запустите с sudo"
    exit 1
  fi
}

create_node_api_script() {
  cat > "$NODE_API_SCRIPT" << 'EOF'
#!/usr/bin/env python3
"""
Simple Node API: management only (no metrics)
"""
from flask import Flask, request, jsonify
import subprocess, os, json
from datetime import datetime

app = Flask(__name__)
AUTH_TOKEN = os.getenv("NODE_API_TOKEN", "your-secret-token")
PORT = int(os.getenv("NODE_API_PORT", "8080"))

def check_auth():
    token = request.headers.get('Authorization')
    return bool(token and token == f"Bearer {AUTH_TOKEN}")

def run(cmd, timeout=30, shell=False):
    try:
        if shell:
            r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        else:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return {"success": r.returncode==0, "output": r.stdout.strip(), "error": r.stderr.strip(), "code": r.returncode}
    except subprocess.TimeoutExpired:
        return {"success": False, "output": "", "error": f"timeout {timeout}s", "code": -1}
    except Exception as e:
        return {"success": False, "output": "", "error": str(e), "code": -1}

def docker_info():
    res = run(['docker','ps','-a','--format','json'])
    if not res["success"]:
        return {"success": False, "error": res["error"], "containers": {}, "raw_containers": []}
    containers, mapping = [], {}
    for line in res["output"].split('\n'):
        if line.strip():
            try:
                obj = json.loads(line)
                containers.append(obj)
                name = obj.get('Names','').strip('/')
                if name:
                    mapping[name] = obj
            except Exception:
                continue
    return {"success": True, "containers": mapping, "raw_containers": containers}

@app.get('/health')
def health():
    return jsonify({"status":"ok","ts":datetime.now().isoformat(),"version":"1.1.0-enhanced"}), 200

@app.get('/api/status')
def status():
    if not check_auth():
        return jsonify({"error":"Unauthorized"}), 401
    
    # Получаем системную информацию
    cpu_result = run(['sh', '-c', "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | sed 's/%us,//'"], timeout=5)
    cpu_usage = cpu_result["output"] if cpu_result["success"] else "N/A"
    
    memory_result = run(['sh', '-c', "free | grep Mem | awk '{printf \"%.1f\", $3/$2 * 100.0}'"], timeout=5)
    memory_usage = memory_result["output"] if memory_result["success"] else "N/A"
    
    uptime_result = run(['uptime', '-p'], timeout=5)
    uptime = uptime_result["output"] if uptime_result["success"] else "N/A"
    
    # Получаем информацию о диске
    disk_result = run(['sh', '-c', "df -h / | tail -1 | awk '{print $5}' | sed 's/%//'"], timeout=5)
    disk_usage = disk_result["output"] if disk_result["success"] else "N/A"
    
    # Определяем тип сервера (панель или нода)
    is_panel = False
    docker_result = run(['docker', 'ps', '--format', '{{.Names}}'], timeout=5)
    if docker_result["success"]:
        container_names = docker_result["output"].lower()
        if 'remnawave' in container_names and 'remnanode' not in container_names:
            is_panel = True
    
    # Получаем информацию о сервисах в зависимости от типа сервера
    services = {}
    if is_panel:
        for service in ['node_exporter']:
            service_result = run(['systemctl', 'is-active', service], timeout=5)
            if service_result["success"]:
                status = service_result["output"].strip().lower()
                if status in ['active', 'running', 'started', 'activating', 'reloading']:
                    services[service] = "active"
                else:
                    ps_result = run(['ps', 'aux'], timeout=5)
                    if ps_result["success"] and service in ps_result["output"]:
                        services[service] = "active"
                    else:
                        services[service] = "inactive"
            else:
                ps_result = run(['ps', 'aux'], timeout=5)
                if ps_result["success"] and service in ps_result["output"]:
                    services[service] = "active"
                else:
                    services[service] = "inactive"
    else:
        for service in ['tblocker', 'node_exporter']:
            service_result = run(['systemctl', 'is-active', service], timeout=5)
            if service_result["success"]:
                status = service_result["output"].strip().lower()
                if status in ['active', 'running', 'started', 'activating', 'reloading']:
                    services[service] = "active"
                else:
                    ps_result = run(['ps', 'aux'], timeout=5)
                    if ps_result["success"] and service in ps_result["output"]:
                        services[service] = "active"
                    else:
                        services[service] = "inactive"
            else:
                ps_result = run(['ps', 'aux'], timeout=5)
                if ps_result["success"] and service in ps_result["output"]:
                    services[service] = "active"
                else:
                    services[service] = "inactive"
    
    xray_version = "N/A"
    xray_status = "inactive"
    if not is_panel:
        xray_version_result = run(['docker', 'exec', 'remnanode', '/usr/local/bin/xray', '-version'], timeout=5)
        if xray_version_result["success"]:
            version_line = xray_version_result["output"].split('\n')[0]
            if 'Xray' in version_line:
                xray_version = version_line.split()[1] if len(version_line.split()) > 1 else "N/A"
        xray_status_result = run(['docker', 'exec', 'remnanode', 'supervisorctl', 'status', 'xray'], timeout=5)
        if xray_status_result["success"]:
            status_line = xray_status_result["output"]
            if 'RUNNING' in status_line or 'active' in status_line.lower():
                xray_status = "running"
        if xray_status == "inactive":
            ps_result = run(['docker', 'exec', 'remnanode', 'ps', 'aux'], timeout=5)
            if ps_result["success"] and 'xray' in ps_result["output"].lower():
                xray_status = "running"
    
    caddy_status = "inactive"
    caddy_system_result = run(['systemctl', 'is-active', 'caddy'], timeout=5)
    if caddy_system_result["success"]:
        status = caddy_system_result["output"].strip().lower()
        if status in ['active', 'running', 'started', 'activating', 'reloading']:
            caddy_status = "running"
    if caddy_status == "inactive":
        docker_result = run(['docker', 'ps', '--filter', 'name=caddy', '--format', '{{.State}}'], timeout=5)
        if docker_result["success"] and 'running' in docker_result["output"].lower():
            caddy_status = "running"
    
    return jsonify({
        "status": "online",
        "ts": datetime.now().isoformat(),
        "cpu": cpu_usage,
        "memory": memory_usage,
        "disk_usage_percent": disk_usage,
        "uptime": uptime,
        "services": services,
        "xray_version": xray_version,
        "xray_status": xray_status,
        "caddy_status": caddy_status,
        "server_type": "panel" if is_panel else "node",
        "docker": docker_info(),
    })

@app.get('/api/docker')
def docker():
    if not check_auth():
        return jsonify({"error":"Unauthorized"}), 401
    return jsonify(docker_info())

@app.post('/api/docker/restart')
def docker_restart():
    if not check_auth():
        return jsonify({"error":"Unauthorized"}), 401
    names = request.json.get('containers',["remnanode","caddy"]) if request.is_json else ["remnanode","caddy"]
    results = {}
    for n in names:
        results[n] = run(['docker','restart',n], timeout=30)
    return jsonify({"message":"restart requested","results":results,"ts":datetime.now().isoformat()})

@app.get('/api/exec')
def exec_get():
    if not check_auth():
        return jsonify({"error":"Unauthorized"}), 401
    cmd = request.args.get('command','echo ok')
    res = run(cmd.split(), timeout=15)
    return jsonify({"command":cmd, **res})

@app.post('/api/reboot')
def reboot():
    if not check_auth():
        return jsonify({"error":"Unauthorized"}), 401
    try:
        subprocess.Popen(['reboot'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return jsonify({"message":"reboot initiated","ts":datetime.now().isoformat()})
    except Exception as e:
        return jsonify({"error":str(e)}), 500

if __name__ == '__main__':
    print(f'Starting Simple Node API on :{PORT}')
    app.run(host='0.0.0.0', port=PORT, debug=False)
EOF
  chmod +x "$NODE_API_SCRIPT"
}

create_systemd_service() {
  cat > "$SYSTEMD_SERVICE_FILE" << EOF
[Unit]
Description=Node API (simple)
After=network.target docker.service

[Service]
Type=simple
User=$NODE_MANAGER_USER
Group=$NODE_MANAGER_USER
WorkingDirectory=$NODE_API_DIR
Environment="NODE_API_TOKEN=$NODE_API_TOKEN"
Environment="NODE_API_PORT=$NODE_API_PORT"
Environment="PYTHONUNBUFFERED=1"
ExecStartPre=/bin/sh -c 'until docker info >/dev/null 2>&1; do sleep 1; done'
ExecStart=$NODE_API_DIR/venv/bin/python $NODE_API_SCRIPT
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
# Hardening
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
CapabilityBoundingSet=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictNamespaces=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
EOF
}

create_user_and_env() {
  # Пользователь
  if ! id -u "$NODE_MANAGER_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$NODE_MANAGER_USER" || true
    log "Создан пользователь $NODE_MANAGER_USER"
  fi
  mkdir -p "$NODE_API_DIR"
  chown -R "$NODE_MANAGER_USER":"$NODE_MANAGER_USER" "$NODE_API_DIR"
  
  # Docker и группа
  apt install -y docker.io || true
  if ! getent group docker >/dev/null; then
    groupadd docker || true
  fi
  usermod -aG docker "$NODE_MANAGER_USER" || true
  
  # Python venv
  sudo -u "$NODE_MANAGER_USER" bash -lc "python3 -m venv $NODE_API_DIR/venv"
  sudo -u "$NODE_MANAGER_USER" bash -lc "$NODE_API_DIR/venv/bin/pip install --upgrade pip"
  sudo -u "$NODE_MANAGER_USER" bash -lc "$NODE_API_DIR/venv/bin/pip install flask flask-cors psutil"
}

verify_service() {
  systemctl daemon-reload
  systemctl enable node-api >/dev/null 2>&1 || true
  systemctl restart node-api

  # Ждем до 20 секунд
  for i in {1..20}; do
    state=$(systemctl is-active node-api || true)
    if [[ "$state" == "active" ]]; then
      log "Сервис node-api активен"
      break
    fi
    sleep 1
  done

  if [[ $(systemctl is-active node-api || true) != "active" ]]; then
    err "Сервис node-api не запустился"
    journalctl -u node-api -n 100 --no-pager || true
    exit 1
  fi

  # Health и status
  if command -v curl >/dev/null 2>&1; then
    curl -fsS http://127.0.0.1:${NODE_API_PORT}/health >/dev/null || warn "Health endpoint недоступен"
    curl -fsS -H "Authorization: Bearer $NODE_API_TOKEN" http://127.0.0.1:${NODE_API_PORT}/api/status >/dev/null || warn "Status endpoint недоступен (проверьте токен)"
  fi
}

main() {
  require_root

  # Токен
  if [ -z "$NODE_API_TOKEN" ]; then
    NODE_API_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
    warn "NODE_API_TOKEN не указан. Сгенерирован временный: $NODE_API_TOKEN"
  fi
  
  # Порт
  NODE_API_PORT="${NODE_API_PORT:-8080}"

  apt update -y
  apt install -y python3 python3-venv python3-pip curl || true

  create_user_and_env
  create_node_api_script
  chown -R "$NODE_MANAGER_USER":"$NODE_MANAGER_USER" "$NODE_API_DIR"
  create_systemd_service

  # UFW
  if command -v ufw >/dev/null 2>&1; then
    ufw allow ${NODE_API_PORT}/tcp || true
  fi

  verify_service
  log "Готово. Проверка: curl -H 'Authorization: Bearer $NODE_API_TOKEN' http://localhost:${NODE_API_PORT}/api/status"
}

main "$@"


