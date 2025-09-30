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
        # Для панели проверяем только node_exporter
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
        # Для ноды проверяем tblocker и node_exporter
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
    
    # Получаем информацию о Xray (только для нод)
    xray_version = "N/A"
    xray_status = "inactive"
    
    if not is_panel:
        # Проверяем Xray через Docker exec
        xray_version_result = run(['docker', 'exec', 'remnanode', '/usr/local/bin/xray', '-version'], timeout=5)
        if xray_version_result["success"]:
            version_line = xray_version_result["output"].split('\n')[0]
            if 'Xray' in version_line:
                xray_version = version_line.split()[1] if len(version_line.split()) > 1 else "N/A"
        
        # Проверяем статус Xray через supervisor
        xray_status_result = run(['docker', 'exec', 'remnanode', 'supervisorctl', 'status', 'xray'], timeout=5)
        if xray_status_result["success"]:
            status_line = xray_status_result["output"]
            if 'RUNNING' in status_line or 'active' in status_line.lower():
                xray_status = "running"
        
        # Дополнительная проверка через ps внутри контейнера
        if xray_status == "inactive":
            ps_result = run(['docker', 'exec', 'remnanode', 'ps', 'aux'], timeout=5)
            if ps_result["success"] and 'xray' in ps_result["output"].lower():
                xray_status = "running"
    
    # Проверяем Caddy (может быть системный процесс или в контейнере)
    caddy_status = "inactive"
    # Сначала проверяем как системный процесс
    caddy_system_result = run(['systemctl', 'is-active', 'caddy'], timeout=5)
    if caddy_system_result["success"]:
        status = caddy_system_result["output"].strip().lower()
        if status in ['active', 'running', 'started', 'activating', 'reloading']:
            caddy_status = "running"
    
    # Если не найден как системный, проверяем в Docker
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
        "debug": {
            "ps_output": run(['ps', 'aux'], timeout=5)["output"][:200] if run(['ps', 'aux'], timeout=5)["success"] else "Failed",
            "tblocker_status": run(['systemctl', 'is-active', 'tblocker'], timeout=5)["output"] if run(['systemctl', 'is-active', 'tblocker'], timeout=5)["success"] else "Failed",
            "node_exporter_status": run(['systemctl', 'is-active', 'node_exporter'], timeout=5)["output"] if run(['systemctl', 'is-active', 'node_exporter'], timeout=5)["success"] else "Failed",
            "caddy_system_status": run(['systemctl', 'is-active', 'caddy'], timeout=5)["output"] if run(['systemctl', 'is-active', 'caddy'], timeout=5)["success"] else "Failed",
            "is_panel": is_panel
        }
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
    print('Starting Simple Node API on :8080')
    app.run(host='0.0.0.0', port=8080, debug=False)
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
User=root
Group=root
WorkingDirectory=$NODE_API_DIR
Environment="NODE_API_TOKEN=$NODE_API_TOKEN"
Environment="PYTHONUNBUFFERED=1"
Environment="VIRTUAL_ENV=$NODE_API_DIR/venv"
Environment="PATH=$NODE_API_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$NODE_API_DIR/venv/bin/python $NODE_API_SCRIPT
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

main() {
  require_root

  if [ -z "$NODE_API_TOKEN" ]; then
    echo -n "Введите NODE_API_TOKEN: "
    read -r NODE_API_TOKEN
    if [ -z "$NODE_API_TOKEN" ]; then
      err "NODE_API_TOKEN пуст"
      exit 1
    fi
  fi

  apt update -y
  apt install -y python3 python3-venv python3-pip python3-flask python3-psutil curl docker.io || true

  mkdir -p "$NODE_API_DIR"
  chown -R "$NODE_MANAGER_USER":"$NODE_MANAGER_USER" "$NODE_API_DIR" 2>/dev/null || true

  # venv и зависимости
  if [ ! -d "$NODE_API_DIR/venv" ]; then
    python3 -m venv "$NODE_API_DIR/venv"
  fi
  "$NODE_API_DIR/venv/bin/pip" install --upgrade pip
  "$NODE_API_DIR/venv/bin/pip" install flask flask-cors psutil

  create_node_api_script
  create_systemd_service

  systemctl daemon-reload
  systemctl enable node-api || true
  systemctl restart node-api || systemctl start node-api

  if command -v ufw >/dev/null 2>&1; then
    ufw allow 8080/tcp || true
  fi

  log "Готово. Проверка: curl -H 'Authorization: Bearer $NODE_API_TOKEN' http://localhost:8080/api/status"
}

main "$@"


