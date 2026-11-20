import io
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

import reconstruct_photos as photos
import reconstruct_video as video


class PhotoPrototypeTests(unittest.TestCase):
    def test_sorted_images_and_too_few(self):
        paths = [Path('b.jpg'), Path('a.PNG'), Path('c.jpeg')]
        with patch.object(Path, 'is_dir', lambda p: p == Path('.')), patch.object(Path, 'iterdir', return_value=iter(paths)), patch.object(Path, 'is_file', return_value=True):
            self.assertEqual([f.path.name for f in photos.load_photos(Path('.'))], ['a.PNG', 'b.jpg', 'c.jpeg'])
        with patch.object(Path, 'is_dir', lambda p: p == Path('.')), patch.object(Path, 'iterdir', return_value=iter(paths[:2])), patch.object(Path, 'is_file', return_value=True):
            with self.assertRaisesRegex(photos.Rejection, 'al menos 3'):
                photos.load_photos(Path('.'))

    def test_rejects_disconnected_or_insufficient_models(self):
        with self.assertRaisesRegex(photos.Rejection, 'conectada'):
            photos.plan_from_models([], 3)
        model = video.SparseModel([], [], video.Intrinsics(1, 1, 1, 1, 0, 0))
        with self.assertRaisesRegex(photos.Rejection, 'registradas'):
            photos.plan_from_models([model], 3)

    def test_cli_registration_failures_explain_capture_and_counts(self):
        intrinsics = video.Intrinsics(1, 1, 1, 1, 0, 0)
        poses = [video.CameraPose(i, ((1,0,0),(0,1,0),(0,0,1)), (float(i),0,0)) for i in range(3)]
        model = video.SparseModel(poses, [], intrinsics)
        frames = [video.ExtractedFrame(i, Path(f'{i}.jpg')) for i in range(30)]
        cases = [([], 'ningún modelo', None), ([model, model], '2 modelos', None),
                 ([model], '3 de 30', 'registradas')]
        for models, expected, extra in cases:
            with self.subTest(expected=expected), patch.object(photos, 'load_photos', return_value=frames), \
                 patch.object(Path, 'exists', return_value=False), \
                 patch.object(video.PycolmapPoseEstimator, 'estimate', return_value=models), \
                 patch('sys.argv', ['reconstruct_photos.py', 'photos', '--work-dir', 'work']), \
                 redirect_stdout(io.StringIO()) as out, redirect_stderr(io.StringIO()) as err:
                self.assertEqual(photos.main(), 1)
                self.assertEqual(out.getvalue(), '')
                message = err.getvalue().lower()
                self.assertIn(expected, message)
                if extra:
                    self.assertIn(extra, message)
                for term in ('lateral', 'detalle', 'fondo', 'solap'):
                    self.assertIn(term, message)
                self.assertNotIn('mueble', message)

    def test_proportional_output_and_contour_rejection(self):
        model = video.SparseModel([video.CameraPose(i, ((1,0,0),(0,1,0),(0,0,1)), (float(i),0,0)) for i in range(3)], [], video.Intrinsics(1,1,1,1,0,0))
        fit = unittest.mock.Mock(walls=[], floor_xz=[], cameras_xz=[(0,0), (1,0), (2,0)], point_count=100)
        piece = unittest.mock.Mock(rooms={'room': fit})
        with patch.object(photos, '_photo_piece', return_value=piece), patch.object(video, '_assembly_factor', return_value=1), patch.object(video.reconstruct, 'propose_contour') as propose:
            propose.return_value = unittest.mock.Mock(corners=[(0,0), (2,0), (2,1), (0,1)])
            result = photos.plan_from_models([model], 3)
            self.assertEqual(result['scale'], 'proporcional_sin_metros')
            self.assertEqual(len(result['contour']), 4)
            propose.return_value = video.reconstruct.ProposalFailed('sin paredes')
            with self.assertRaisesRegex(photos.Rejection, 'sin paredes'):
                photos.plan_from_models([model], 3)


if __name__ == '__main__':
    unittest.main()
