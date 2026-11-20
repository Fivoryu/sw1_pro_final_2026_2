"""Prototipo local: fotografías ordenadas a contorno proporcional, sin sensores."""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import reconstruct_video as video


class Rejection(ValueError):
    """No hay evidencia suficiente para proponer un plano."""


def load_photos(folder: Path) -> list[video.ExtractedFrame]:
    if not folder.is_dir():
        raise Rejection('La carpeta de fotos no existe.')
    entries = list(folder.iterdir())
    if any(p.is_dir() for p in entries):
        raise Rejection('Usá una carpeta sin subcarpetas para evitar imágenes adicionales.')
    if any(p.is_file() and p.suffix.lower() not in {'.jpg', '.jpeg', '.png'} for p in entries):
        raise Rejection('La carpeta debe contener únicamente fotos JPG o PNG.')
    images = sorted((p for p in entries if p.is_file()), key=lambda p: p.name)
    if len(images) < 3:
        raise Rejection('Se necesitan al menos 3 fotos solapadas; capturá más vistas de la habitación.')
    return [video.ExtractedFrame(i, p.resolve()) for i, p in enumerate(images)]


def _photo_piece(model: video.SparseModel) -> video._Piece:
    # The camera-up fallback assumes upright photos; it does not use gravity samples.
    up = tuple(sum(video._mv(p.rotation, (0.0, -1.0, 0.0))[i] for p in model.poses) for i in range(3))
    norm = math.sqrt(sum(x*x for x in up))
    if norm / len(model.poses) < 0.8:
        raise Rejection('Las orientaciones de cámara no coinciden; repetí las fotos manteniendo la cámara vertical.')
    indices = {p.frame_index: 0 for p in model.poses}  # _align uses only membership, not time.
    piece = video._align(model, tuple(x / norm for x in up), 'cameras', indices)
    video._fit_rooms(piece, [{'id': 'room', 'name': 'Habitación'}], {i: 'room' for i in indices})
    return piece


def plan_from_models(models: list[video.SparseModel], photo_count: int) -> dict:
    capture_hint = ('Repetí la captura con desplazamiento lateral entre vistas solapadas, '
                    'manteniendo simultáneamente un detalle cercano y el fondo visibles; '
                    'no basta con girar la cámara desde un mismo punto.')
    if not models:
        raise Rejection(f'No se obtuvo ningún modelo para una reconstrucción conectada. {capture_hint}')
    if len(models) != 1:
        raise Rejection(f'Se obtuvieron {len(models)} modelos desconectados, no una reconstrucción conectada única. {capture_hint}')
    model = models[0]
    if len(model.poses) < 3 or len(model.poses) / photo_count < 0.7:
        raise Rejection(f'Hay pocas fotos registradas: {len(model.poses)} de {photo_count}. {capture_hint}')
    piece = _photo_piece(model)
    fit = piece.rooms.get('room')
    if fit is None:
        raise Rejection('No hay puntos suficientes; fotografiá paredes texturizadas desde varias posiciones.')
    try:
        factor = video._assembly_factor(piece)
    except video.InvalidPackage as error:
        raise Rejection('La trayectoria no tiene desplazamiento suficiente; caminá entre las fotos.') from error
    segments = [s for wall in fit.walls if (s := video.reconstruct.fit_wall_segment([(x * factor, y * factor, z * factor) for x, y, z in wall.points]))]
    axis = video.reconstruct.dominant_axis([(s.start, s.end) for s in segments]) if segments else None
    proposal = video.reconstruct.propose_contour(
        [(s.start, s.end) for s in segments],
        [[(x * factor, z * factor) for x, z in fit.floor_xz]],
        [(x * factor, z * factor) for x, z in fit.cameras_xz], axis=axis)
    if isinstance(proposal, video.reconstruct.ProposalFailed):
        raise Rejection(f'No se pudo proponer un contorno: {proposal.message} Capturá más paredes y esquinas.')
    return {'scale': 'proporcional_sin_metros', 'contour': [{'x': x, 'z': z} for x, z in proposal.corners],
            'registered_photos': len(model.poses), 'photo_count': photo_count,
            'warning': 'Contorno estimado; unidades arbitrarias, no metros. Revisar antes de usar.'}


def main() -> int:
    parser = argparse.ArgumentParser(
        description='Prototipo local de plano proporcional a partir de fotos.',
        epilog=('Desplazate lateralmente entre vistas solapadas y mantené visibles a la vez '
                'un detalle cercano y el fondo; no basta girar la cámara.'))
    parser.add_argument('folder', type=Path, help='Carpeta de fotos ordenadas por nombre')
    parser.add_argument('--work-dir', type=Path, required=True, help='Directorio nuevo para archivos temporales SfM')
    args = parser.parse_args()
    try:
        frames = load_photos(args.folder)
        work = args.work_dir.resolve()
        folder = args.folder.resolve()
        if work.exists() or work == folder or folder in work.parents or work in folder.parents:
            raise Rejection('Elegí un directorio de trabajo nuevo, separado de la carpeta de fotos.')
        models = video.PycolmapPoseEstimator().estimate(frames, work)
        print(json.dumps(plan_from_models(models, len(frames)), ensure_ascii=False, indent=2))
        return 0
    except (Rejection, video.ExternalToolMissing, video.VideoRuntimeError, OSError, ValueError) as error:
        print(f'No se generó el plano: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
