/// Pure spatial-capture domain (F07): normalizes AR captures, validates
/// contours and openings, records tolerances, joins rooms through doors and
/// builds the scene contract v2 document. No Flutter, plugins or I/O.
library;

export 'capture_models.dart';
export 'contour_proposal.dart';
export 'door_connection.dart';
export 'geometry.dart'
    show
        FloorPoint,
        edgeLengths,
        perimeter,
        polygonArea,
        signedArea,
        pointInPolygon,
        segmentsIntersect;
export 'manual_room.dart';
export 'scale_correction.dart';
export 'scene_builder.dart';
export 'validation.dart';
