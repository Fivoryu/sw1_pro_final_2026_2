import React, { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';

const roomData = {
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
      ]
    }
  ]
};

export const SceneViewer: React.FC = () => {
  const mountRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!mountRef.current) return;

    // 1. Escena y color de fondo más profesional (gris oscuro)
    const scene = new THREE.Scene();
    scene.background = new THREE.Color('#222222');

    // 2. Cuadrícula de arquitecto (Grid) para el suelo
    const gridHelper = new THREE.GridHelper(10, 10, '#888888', '#444444');
    gridHelper.position.set(2, 0, 1.5);
    scene.add(gridHelper);

    const camera = new THREE.PerspectiveCamera(75, 800 / 600, 0.1, 1000);
    camera.position.set(5, 6, 6);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(800, 600);
    mountRef.current.appendChild(renderer.domElement);

    // 3. Controles para rotar con el ratón
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(2, 1, 1.5); // Centrar la rotación en el medio del cuarto

    const room = roomData.rooms[0];

    // 4. Suelo transparente con bordes
    const floorGeometry = new THREE.PlaneGeometry(4, 3);
    const floorMaterial = new THREE.MeshBasicMaterial({ color: '#3a7bd5', transparent: true, opacity: 0.5, side: THREE.DoubleSide });
    const floor = new THREE.Mesh(floorGeometry, floorMaterial);
    floor.rotation.x = Math.PI / 2;
    floor.position.set(2, 0, 1.5);
    scene.add(floor);

    // 5. Paredes con bordes negros para dar profundidad
    const wallMaterial = new THREE.MeshBasicMaterial({ color: '#e67e22', transparent: true, opacity: 0.8, side: THREE.DoubleSide });
    const lineMaterial = new THREE.LineBasicMaterial({ color: 0x000000, linewidth: 2 });
    
    const contours = room.contours;
    for (let i = 0; i < contours.length; i++) {
      const p1 = contours[i];
      const p2 = contours[(i + 1) % contours.length];

      const width = Math.hypot(p2.x - p1.x, p2.z - p1.z);
      const wallGeometry = new THREE.PlaneGeometry(width, room.height);
      const wall = new THREE.Mesh(wallGeometry, wallMaterial);

      wall.position.x = (p1.x + p2.x) / 2;
      wall.position.z = (p1.z + p2.z) / 2;
      wall.position.y = room.height / 2;
      wall.rotation.y = Math.atan2(p1.z - p2.z, p2.x - p1.x);

      // Dibujar las líneas de los bordes
      const edges = new THREE.EdgesGeometry(wallGeometry);
      const line = new THREE.LineSegments(edges, lineMaterial);
      wall.add(line);

      scene.add(wall);
    }

    const animate = () => {
      requestAnimationFrame(animate);
      controls.update(); // Necesario para la suavidad de rotación
      renderer.render(scene, camera);
    };
    animate();

    return () => {
      if (mountRef.current) {
        mountRef.current.removeChild(renderer.domElement);
      }
      renderer.dispose();
    };
  }, []);

  return (
    <div style={{ padding: '20px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      <h2 style={{ fontFamily: 'sans-serif', color: '#333' }}>Visor 3D Paramétrico - F06.2</h2>
      <p style={{ fontFamily: 'sans-serif', color: '#666' }}><b>Haz clic y arrastra</b> sobre el recuadro para rotar la cámara</p>
      <div ref={mountRef} style={{ border: '3px solid #ccc', borderRadius: '8px', overflow: 'hidden', cursor: 'grab' }} />
    </div>
  );
};