# Servicio de inferencia de F08 — imagen CPU, sin GPU.
#
# Los pesos NO se hornean en la imagen: se descargan una sola vez a un volumen
# nombrado (TORCH_HOME) y quedan cacheados entre ejecuciones. Así la imagen se
# mantiene chica y los pesos se pueden auditar por separado.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TORCH_HOME=/cache/torch

WORKDIR /app
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /app/requirements.txt

WORKDIR /work
ENTRYPOINT ["python", "/work/detect.py"]
CMD ["--help"]
