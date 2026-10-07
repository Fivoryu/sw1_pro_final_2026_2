import React, { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { DragControls } from 'three/examples/jsm/controls/DragControls.js';

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
};

export const SceneViewer: React.FC = () => {
  const mountRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!mountRef.current) return;
    
    // SOLUCIÓN: Limpiar el contenedor a la fuerza antes de dibujar nada para evitar duplicados
    mountRef.current.innerHTML = '';

    const scene = new THREE.Scene();
    scene.background = new THREE.Color('#222222');

    const gridHelper = new THREE.GridHelper(10, 10, '#888888', '#444444');
    gridHelper.position.set(2, 0, 1.5);
    scene.add(gridHelper);

    const camera = new THREE.PerspectiveCamera(75, 800 / 600, 0.1, 1000);
    camera.position.set(5, 6, 6);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(800, 600);
    mountRef.current.appendChild(renderer.domElement);

    const orbitControls = new OrbitControls(camera, renderer.domElement);
    orbitControls.enableDamping = true;
    orbitControls.target.set(2, 1, 1.5);

    const room = roomData.rooms[0];

    const floorGeometry = new THREE.PlaneGeometry(4, 3);
    const floorMaterial = new THREE.MeshBasicMaterial({ color: '#3a7bd5', transparent: true, opacity: 0.5, side: THREE.DoubleSide });
    const floor = new THREE.Mesh(floorGeometry, floorMaterial);
    floor.rotation.x = Math.PI / 2;
    floor.position.set(2, 0, 1.5);
    scene.add(floor);

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

      const edges = new THREE.EdgesGeometry(wallGeometry);
      const line = new THREE.LineSegments(edges, lineMaterial);
      wall.add(line);

      scene.add(wall);
    }

    const draggableObjects: THREE.Mesh[] = [];

    roomData.objects.forEach(obj => {
      const geometry = new THREE.BoxGeometry(obj.dimensions.width, obj.dimensions.height, obj.dimensions.depth);
      const material = new THREE.MeshBasicMaterial({ color: obj.color });
      const mesh = new THREE.Mesh(geometry, material);
      
      const yPosition = obj.position.y + (obj.dimensions.height / 2);
      mesh.position.set(obj.position.x, yPosition, obj.position.z);
      
      mesh.userData = { 
        originalY: yPosition,
        halfWidth: obj.dimensions.width / 2,
        halfDepth: obj.dimensions.depth / 2
      };

      const edges = new THREE.EdgesGeometry(geometry);
      const line = new THREE.LineSegments(edges, new THREE.LineBasicMaterial({ color: 0x000000 }));
      mesh.add(line);

      scene.add(mesh);
      draggableObjects.push(mesh);
    });

    const dragControls = new DragControls(draggableObjects, camera, renderer.domElement);
    
    dragControls.addEventListener('dragstart', () => {
      orbitControls.enabled = false;
    });

    dragControls.addEventListener('drag', (event) => {
      const obj = event.object;
      
      obj.position.y = obj.userData.originalY;

      const minX = 0 + obj.userData.halfWidth;
      const maxX = 4 - obj.userData.halfWidth;
      const minZ = 0 + obj.userData.halfDepth;
      const maxZ = 3 - obj.userData.halfDepth;

      if (obj.position.x < minX) obj.position.x = minX;
      if (obj.position.x > maxX) obj.position.x = maxX;
      if (obj.position.z < minZ) obj.position.z = minZ;
      if (obj.position.z > maxZ) obj.position.z = maxZ;
    });

    dragControls.addEventListener('dragend', () => {
      orbitControls.enabled = true;
    });

    let animationId: number;
    const animate = () => {
      animationId = requestAnimationFrame(animate);
      orbitControls.update();
      renderer.render(scene, camera);
    };
    animate();

    return () => {
      cancelAnimationFrame(animationId);
      orbitControls.dispose();
      dragControls.dispose();
      renderer.dispose();
      if (mountRef.current) {
        mountRef.current.innerHTML = ''; // Limpiar todo al salir
      }
    };
  }, []);

  return (
    <div style={{ padding: '20px', display: 'flex', flexDirection: 'column', alignItems: 'center', backgroundColor: '#f0f0f0', minHeight: '100vh' }}>
      <h2 style={{ fontFamily: 'sans-serif', color: '#333' }}>Visor 3D Paramétrico - F06.3</h2>
      <p style={{ fontFamily: 'sans-serif', color: '#666' }}>El cubo rojo ahora tiene <b>colisiones</b> y no puede salir de la habitación.</p>
      <div ref={mountRef} style={{ border: '3px solid #333', borderRadius: '8px', overflow: 'hidden', cursor: 'grab', boxShadow: '0 4px 8px rgba(0,0,0,0.2)' }} />
    </div>
  );
};