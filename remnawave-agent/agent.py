#!/usr/bin/env python3
"""
Remnawave Agent API
Легковесный API сервис для управления компонентами Remnawave на сервере
"""

import os
import json
import subprocess
import logging
from pathlib import Path
from typing import Optional
from fastapi import FastAPI, HTTPException, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv

load_dotenv()

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(title="Remnawave Agent API")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Токен из переменной окружения
AGENT_TOKEN = os.getenv('AGENT_TOKEN', '')
if not AGENT_TOKEN:
    logger.warning("AGENT_TOKEN не установлен! Установите переменную окружения AGENT_TOKEN")

# Компоненты Remnawave
COMPONENTS = {
    'panel': {
        'name': 'Remnawave Panel',
        'directory': Path('/opt/remnawave'),
        'type': 'panel'
    },
    'node': {
        'name': 'Remnawave Node',
        'directory': Path('/opt/remnanode'),
        'type': 'node'
    },
    'subscription': {
        'name': 'Remnawave Subscription Page',
        'directory': Path('/opt/remnawave/subscription'),
        'type': 'subscription'
    }
}


def verify_token(authorization: Optional[str] = Header(None)):
    """Проверить токен авторизации"""
    if not AGENT_TOKEN:
        raise HTTPException(status_code=500, detail="Agent token not configured")
    
    if not authorization:
        raise HTTPException(status_code=401, detail="Authorization header required")
    
    if not authorization.startswith('Bearer '):
        raise HTTPException(status_code=401, detail="Invalid authorization format")
    
    token = authorization.replace('Bearer ', '')
    if token != AGENT_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid token")
    
    return token


class UpdateRequest(BaseModel):
    component_type: str


@app.get("/health")
async def health():
    """Healthcheck"""
    return {"status": "ok"}


@app.get("/api/components")
async def get_components(_: str = Depends(verify_token)):
    """Получить список установленных компонентов"""
    installed = []
    
    for key, component in COMPONENTS.items():
        directory = component['directory']
        compose_file = directory / 'docker-compose.yml'
        
        if directory.exists() and compose_file.exists():
            installed.append({
                'type': component['type'],
                'name': component['name'],
                'directory': str(directory),
            })
    
    return {'components': installed}


@app.get("/api/components/{component_type}/info")
async def get_component_info(component_type: str, _: str = Depends(verify_token)):
    """Получить информацию о компоненте"""
    component = COMPONENTS.get(component_type)
    if not component or not component['directory'].exists():
        raise HTTPException(status_code=404, detail=f"Component {component_type} not found")
    
    directory = component['directory']
    compose_file = directory / 'docker-compose.yml'
    
    if not compose_file.exists():
        raise HTTPException(status_code=404, detail=f"docker-compose.yml not found for {component_type}")
    
    # Получаем статус
    status = 'stopped'
    try:
        result = subprocess.run(
            ['docker', 'compose', 'ps', '-q'],
            cwd=directory,
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0 and result.stdout.strip():
            status = 'running'
    except Exception as e:
        logger.error(f"Ошибка получения статуса: {e}")
        status = 'unknown'
    
    # Получаем образ из docker-compose.yml
    image = None
    version = None
    try:
        with open(compose_file, 'r', encoding='utf-8') as f:
            content = f.read()
            import re
            image_match = re.search(r'image:\s*(.+)', content)
            if image_match:
                image = image_match.group(1).strip()
                
                # Получаем версию образа из docker
                if image:
                    try:
                        result = subprocess.run(
                            ['docker', 'images', '--format', '{{.Tag}}', image],
                            capture_output=True,
                            text=True,
                            timeout=5
                        )
                        if result.returncode == 0 and result.stdout.strip():
                            version = result.stdout.strip().split('\n')[0]
                    except:
                        pass
    except Exception as e:
        logger.error(f"Ошибка получения образа: {e}")
    
    return {
        'type': component_type,
        'name': component['name'],
        'status': status,
        'image': image,
        'version': version,
        'directory': str(directory)
    }


@app.post("/api/components/{component_type}/update")
async def update_component(component_type: str, _: str = Depends(verify_token)):
    """Обновить компонент"""
    component = COMPONENTS.get(component_type)
    if not component or not component['directory'].exists():
        raise HTTPException(status_code=404, detail=f"Component {component_type} not found")
    
    directory = component['directory']
    
    try:
        commands = [
            ['docker', 'compose', 'pull'],
            ['docker', 'compose', 'down'],
            ['docker', 'compose', 'up', '-d']
        ]
        
        output_lines = []
        for cmd in commands:
            result = subprocess.run(
                cmd,
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=300  # 5 минут
            )
            
            if result.stdout:
                output_lines.append(result.stdout)
            if result.stderr:
                output_lines.append(result.stderr)
            
            if result.returncode != 0:
                raise HTTPException(
                    status_code=500,
                    detail=f"Ошибка при выполнении команды: {' '.join(cmd)}\n{result.stderr}"
                )
        
        # Получаем обновленную информацию
        info = await get_component_info(component_type, _)
        
        return {
            'success': True,
            'message': f'{component["name"]} успешно обновлен',
            'output': '\n'.join(output_lines),
            'info': info
        }
    except HTTPException:
        raise
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=500, detail="Таймаут при выполнении команды обновления")
    except Exception as e:
        logger.error(f"Ошибка обновления: {e}")
        raise HTTPException(status_code=500, detail=f"Ошибка обновления: {str(e)}")


@app.get("/api/components/{component_type}/check-update")
async def check_update(component_type: str, _: str = Depends(verify_token)):
    """Проверить наличие новой версии"""
    component = COMPONENTS.get(component_type)
    if not component or not component['directory'].exists():
        raise HTTPException(status_code=404, detail=f"Component {component_type} not found")
    
    directory = component['directory']
    compose_file = directory / 'docker-compose.yml'
    
    if not compose_file.exists():
        raise HTTPException(status_code=404, detail=f"docker-compose.yml not found")
    
    try:
        # Получаем текущий образ
        with open(compose_file, 'r', encoding='utf-8') as f:
            content = f.read()
            import re
            image_match = re.search(r'image:\s*(.+)', content)
            if not image_match:
                raise HTTPException(status_code=404, detail="Image not found in docker-compose.yml")
            
            image = image_match.group(1).strip()
            
        # Получаем текущую версию
        current_version = None
        try:
            result = subprocess.run(
                ['docker', 'images', '--format', '{{.Tag}}', image],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                current_version = result.stdout.strip().split('\n')[0]
        except:
            pass
        
        # Проверяем новую версию через docker pull (dry-run)
        # Для этого делаем docker pull и смотрим, что скачалось
        has_update = False
        try:
            result = subprocess.run(
                ['docker', 'compose', 'pull', '--dry-run'],
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=60
            )
            # Если docker compose pull --dry-run показывает изменения, значит есть обновление
            # Но --dry-run может не поддерживаться во всех версиях
            # Альтернатива - просто сделать pull и сравнить
        except:
            pass
        
        # Альтернативный способ - делаем pull и проверяем, изменился ли образ
        # Это не идеально, но работает
        new_image_id = None
        try:
            # Получаем ID образа до pull
            result_before = subprocess.run(
                ['docker', 'images', '--format', '{{.ID}}', image],
                capture_output=True,
                text=True,
                timeout=5
            )
            image_id_before = result_before.stdout.strip().split('\n')[0] if result_before.returncode == 0 else None
            
            # Делаем pull (но не применяем)
            result_pull = subprocess.run(
                ['docker', 'compose', 'pull'],
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=300
            )
            
            if result_pull.returncode == 0:
                # Получаем ID образа после pull
                result_after = subprocess.run(
                    ['docker', 'images', '--format', '{{.ID}}', image],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                image_id_after = result_after.stdout.strip().split('\n')[0] if result_after.returncode == 0 else None
                
                # Если ID изменился или появился новый образ, значит есть обновление
                if image_id_after and image_id_after != image_id_before:
                    has_update = True
                    # Получаем новую версию
                    result_version = subprocess.run(
                        ['docker', 'images', '--format', '{{.Tag}}', image],
                        capture_output=True,
                        text=True,
                        timeout=5
                    )
                    if result_version.returncode == 0 and result_version.stdout.strip():
                        new_version = result_version.stdout.strip().split('\n')[0]
        except Exception as e:
            logger.error(f"Ошибка проверки обновления: {e}")
        
        return {
            'has_update': has_update,
            'current_version': current_version,
            'image': image
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Ошибка проверки обновления: {e}")
        raise HTTPException(status_code=500, detail=f"Ошибка проверки обновления: {str(e)}")


if __name__ == '__main__':
    import uvicorn
    port = int(os.getenv('AGENT_PORT', '8080'))
    uvicorn.run(app, host='0.0.0.0', port=port)

