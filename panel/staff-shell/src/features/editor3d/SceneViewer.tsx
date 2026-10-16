import React, { useEffect, useRef, useState } from 'react';
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
      "name": "Sofá Modular Rojo",
      "price": 599.99,
      "position": { "x": 1, "y": 0, "z": 1 },
      "dimensions": { "width": 0.5, "height": 0.5, "depth": 0.5 },
      "color": "red"
    }
  ]
};

export const SceneViewer: React.FC = () => {
  const mountRef = useRef<HTMLDivElement>(null);
  const [selectedItem, setSelectedItem] = useState<{ name: string; price: number } | null>(null);

  useEffect(() => {
    if (!mountRef.current) return;
    mountRef.current.innerHTML = '';

    const scene = new THREE.Scene();
    scene.background = new THREE.Color('#222222');

    const gridHelper = new THREE.GridHelper(10, 10, '#888888', '#444444');
    gridHelper.position.set(2, 0, 1.5);
    scene.add(gridHelper);

    const camera = new THREE.PerspectiveCamera(75, 800 / 600, 0.1, 1000);
    // Cámara inicial desde afuera (perspectiva de maqueta)
    camera.position.set(5, 6, 7);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(800, 500); // Ajustamos un poco la altura para que encaje mejor en el diseño
    mountRef.current.appendChild(renderer.domElement);

    const orbitControls = new OrbitControls(camera, renderer.domElement);
    orbitControls.enableDamping = true;
    orbitControls.target.set(2, 1.6, 1.5);
    orbitControls.maxPolarAngle = Math.PI / 2;

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
        halfDepth: obj.dimensions.depth / 2,
        name: obj.name,
        price: obj.price
      };

      const edges = new THREE.EdgesGeometry(geometry);
      const line = new THREE.LineSegments(edges, new THREE.LineBasicMaterial({ color: 0x000000 }));
      mesh.add(line);
      scene.add(mesh);
      draggableObjects.push(mesh);
    });

    const dragControls = new DragControls(draggableObjects, camera, renderer.domElement);
    dragControls.addEventListener('dragstart', () => orbitControls.enabled = false);
    dragControls.addEventListener('drag', (event) => {
      const obj = event.object;
      obj.position.y = obj.userData.originalY;
      const minX = obj.userData.halfWidth;
      const maxX = 4 - obj.userData.halfWidth;
      const minZ = obj.userData.halfDepth;
      const maxZ = 3 - obj.userData.halfDepth;
      if (obj.position.x < minX) obj.position.x = minX;
      if (obj.position.x > maxX) obj.position.x = maxX;
      if (obj.position.z < minZ) obj.position.z = minZ;
      if (obj.position.z > maxZ) obj.position.z = maxZ;
    });
    dragControls.addEventListener('dragend', () => orbitControls.enabled = true);

    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2();
    const onClick = (event: MouseEvent) => {
      const rect = renderer.domElement.getBoundingClientRect();
      mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
      raycaster.setFromCamera(mouse, camera);
      const intersects = raycaster.intersectObjects(draggableObjects);
      if (intersects.length > 0) {
        const object = intersects[0].object;
        setSelectedItem({ name: object.userData.name, price: object.userData.price });
      } else {
        setSelectedItem(null);
      }
    };
    renderer.domElement.addEventListener('click', onClick);

    const keys = { w: false, a: false, s: false, d: false };
    const handleKeyDown = (e: KeyboardEvent) => {
      const key = e.key.toLowerCase();
      if (keys.hasOwnProperty(key)) keys[key as keyof typeof keys] = true;
    };
    const handleKeyUp = (e: KeyboardEvent) => {
      const key = e.key.toLowerCase();
      if (keys.hasOwnProperty(key)) keys[key as keyof typeof keys] = false;
    };
    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);

    let animationId: number;
    const animate = () => {
      animationId = requestAnimationFrame(animate);
      const speed = 0.05;
      const direction = new THREE.Vector3();
      camera.getWorldDirection(direction);
      direction.y = 0; 
      direction.normalize();
      const right = new THREE.Vector3();
      right.crossVectors(camera.up, direction).normalize();

      if (keys.w) { camera.position.addScaledVector(direction, speed); orbitControls.target.addScaledVector(direction, speed); }
      if (keys.s) { camera.position.addScaledVector(direction, -speed); orbitControls.target.addScaledVector(direction, -speed); }
      if (keys.a) { camera.position.addScaledVector(right, speed); orbitControls.target.addScaledVector(right, speed); }
      if (keys.d) { camera.position.addScaledVector(right, -speed); orbitControls.target.addScaledVector(right, -speed); }

      orbitControls.update();
      renderer.render(scene, camera);
    };
    animate();

    return () => {
      cancelAnimationFrame(animationId);
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
      renderer.domElement.removeEventListener('click', onClick);
      orbitControls.dispose();
      dragControls.dispose();
      renderer.dispose();
      if (mountRef.current) mountRef.current.innerHTML = '';
    };
  }, []);

  // --- NUEVA ESTRUCTURA HTML BASADA EN EL DISEÑO DE TU COMPAÑERO ---
  return (
    <div className="protected-staff-workspace">
      <header className="protected-staff-header">
        <div className="protected-staff-brand" aria-label="RoomForge">
          <span className="protected-staff-brand__mark" aria-hidden="true">RF</span>
          <span className="brand-wordmark">ROOMFORGE</span>
        </div>
        <div className="protected-staff-identity">
          <span>Área de diseño</span>
          <span>agente@roomforge.test</span>
        </div>
        <button className="staff-logout-action" type="button">
          Cerrar sesión
        </button>
      </header>

      <div className="protected-staff-body">
        <nav aria-label="Navegación principal" className="protected-staff-navigation">
          <span aria-current="page">Visor 3D</span>
        </nav>
        
        <main className="protected-staff-content">
          <p className="eyebrow">ESPACIO PRIVADO</p>
          <h1>Editor 3D de Inmuebles</h1>
          
          <div style={{ position: 'relative', marginTop: '20px', backgroundColor: '#fff', padding: '20px', borderRadius: '12px', boxShadow: '0 2px 8px rgba(0,0,0,0.05)' }}>
            <p style={{ marginBottom: '15px', color: '#4a5568' }}>Utiliza el ratón para rotar la cámara y hacer clic en los muebles. Usa <b>W, A, S, D</b> para moverte.</p>
            
            <div style={{ position: 'relative', display: 'flex', justifyContent: 'center' }}>
              <div ref={mountRef} style={{ border: '1px solid #e2e8f0', borderRadius: '8px', overflow: 'hidden', cursor: 'crosshair' }} />
              
              {selectedItem && (
                <div style={{
                  position: 'absolute',
                  top: '20px',
                  right: '20px',
                  backgroundColor: 'rgba(255, 255, 255, 0.95)',
                  padding: '15px',
                  borderRadius: '8px',
                  boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
                  borderLeft: '5px solid #0f766e',
                  fontFamily: 'sans-serif',
                  pointerEvents: 'none'
                }}>
                  <h3 style={{ margin: '0 0 8px 0', color: '#1f2937', fontSize: '16px' }}>{selectedItem.name}</h3>
                  <p style={{ margin: 0, color: '#0f766e', fontWeight: 'bold', fontSize: '18px' }}>
                    ${selectedItem.price.toFixed(2)}
                  </p>
                </div>
              )}
            </div>
          </div>
        </main>
      </div>
    </div>
  );
};