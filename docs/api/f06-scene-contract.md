# Contrato de Escena 3D (F06)

Define la estructura JSON estandarizada para representar inmuebles paramétricos antes de su renderizado.

## Estructura Base (Fixture Sintético)

```json
{
  "version": "1.0",
  "unit": "meters",
  "rooms": [
    {
      "id": "room_main",
      "height": 2.4,
      "contours": [
        { "x": 0, "z": 0 },
        { "x": 4, "z": 0 },
        { "x": 4, "z": 3 },
        { "x": 0, "z": 3 }
      ],
      "openings": [
        {
          "id": "door_1",
          "type": "door",
          "position": { "x": 2, "y": 0, "z": 0 },
          "width": 0.9,
          "height": 2.1
        }
      ]
    }
  ],
  "objects": [
    {
      "id": "ref_cube_1",
      "type": "placeholder",
      "position": { "x": 1, "y": 0, "z": 1 },
      "dimensions": { "width": 0.5, "height": 0.5, "depth": 0.5 },
      "color": "red"
    }
  ]
}
```