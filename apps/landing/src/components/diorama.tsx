import { SparkRenderer } from "@sparkjsdev/spark";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { useEffect, useLayoutEffect, useMemo, useRef } from "react";
import * as THREE from "three";
import { DioramaScene, gradientEnvironment, Lighting } from "../scene/scene.js";

// The room and Mochi are vendored from nooki-scene (src/scene), the web port of the app's DioramaScene.
const roomTarget = new THREE.Vector3(-0.06, 0.25, 0.06);
const direction = new THREE.Vector3(1, 0.82, 1).normalize();

type Props = {
  /** The pinned story section; how far it has scrolled lights the room and brings the camera to Mochi. */
  storyId: string;
  reduceMotion: boolean;
  onPet: (anchor: { x: number; y: number }) => void;
  onReady: () => void;
};

export function Diorama(props: Props) {
  const diorama = useMemo(() => new DioramaScene(), []);
  return (
    <Canvas
      shadows="soft"
      dpr={[1, 2]}
      camera={{ fov: 22, near: 0.01, far: 60 }}
      gl={{ alpha: true, antialias: true }}
      // The canvas fades in from scale 0.94 (hero-stage.tsx); size it from the layout box, not the transformed one.
      resize={{ offsetSize: true }}
    >
      <Stage diorama={diorama} {...props} />
    </Canvas>
  );
}

const smooth = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};

function Stage({
  diorama,
  storyId,
  reduceMotion,
  onPet,
  onReady,
}: Props & { diorama: DioramaScene }) {
  const { gl, scene, camera, size } = useThree();

  useLayoutEffect(() => {
    gl.toneMapping = THREE.NeutralToneMapping;
    scene.environment = gradientEnvironment(gl);
    const spark = new SparkRenderer({ renderer: gl });
    scene.add(spark);
    onReady();
    return () => {
      scene.remove(spark);
    };
  }, [gl, scene, onReady]);

  const focusUntil = useRef(-1);
  const look = useMemo(
    () => ({
      target: roomTarget.clone(),
      distance: 6,
      shift: 0,
      lift: 0,
      goal: new THREE.Vector3(),
    }),
    [],
  );
  usePointer(diorama, () => {
    focusUntil.current = performance.now() + 3500;
    onPet({ x: size.width / 2, y: size.height * 0.42 });
  });
  const dragging = useDragToTurn(diorama);

  const environment = useMemo(
    () =>
      new THREE.Color(Lighting.environment.top).lerp(
        new THREE.Color(Lighting.environment.bottom),
        0.5,
      ),
    [],
  );
  useFrame(({ clock }, delta) => {
    const story = document.getElementById(storyId)?.getBoundingClientRect();
    const progress = story
      ? Math.min(1, Math.max(0, -story.top / Math.max(1, story.height - innerHeight)))
      : 1;
    const lit = reduceMotion ? 1 : smooth(0.12, 0.42, progress);
    const close = Math.max(
      smooth(0.5, 0.78, progress),
      performance.now() < focusUntil.current ? 1 : 0,
    );
    const wide = size.width >= 900;

    // Dusk to lamplight: the one mood dial, as in the app's lighting.
    gl.toneMappingExposure = THREE.MathUtils.lerp(0.32, Lighting.exposure, lit);
    scene.environmentIntensity = THREE.MathUtils.lerp(0.12, Lighting.environment.intensity, lit);

    const rest = size.width / size.height < 0.95 ? 7.4 : 4.9;
    look.goal.copy(roomTarget).lerp(diorama.catAnchor().setY(diorama.eyeHeight() - 0.03), close);
    const ease = reduceMotion ? 1 : 1 - Math.exp(-delta * 3);
    look.target.lerp(look.goal, ease);
    look.distance += (THREE.MathUtils.lerp(rest, 1.55, close) - look.distance) * ease;
    // The room sits beside the copy (right of it on a wide screen, above it on a phone), and slides to the
    // centre as the camera closes in.
    look.shift += ((wide ? 0.2 * (1 - close) : 0) - look.shift) * ease;
    look.lift += ((wide ? 0 : 0.2 * (1 - close)) - look.lift) * ease;
    camera.position.copy(direction).setLength(look.distance).add(look.target);
    camera.lookAt(look.target);
    if (camera instanceof THREE.PerspectiveCamera) {
      camera.setViewOffset(
        size.width,
        size.height,
        -size.width * look.shift,
        size.height * look.lift,
        size.width,
        size.height,
      );
    }

    if (!reduceMotion && !dragging.current && close < 0.5)
      diorama.setYaw(Math.sin(clock.elapsedTime * 0.18) * 0.22);
    diorama.watch(camera.position);
    diorama.tick(Math.min(delta, 0.1));
    diorama.tintSplats(environment, scene.environmentIntensity);
  });

  return <primitive object={diorama.root} />;
}

/** Mochi follows the pointer at her eye height, and a tap on her (not a drag) pets her. */
function usePointer(diorama: DioramaScene, onTap: () => void) {
  const { gl, camera } = useThree();
  const tapRef = useRef(onTap);
  tapRef.current = onTap;

  useEffect(() => {
    const element = gl.domElement;
    const raycaster = new THREE.Raycaster();
    const eyePlane = new THREE.Plane(new THREE.Vector3(0, 1, 0));
    let start: { x: number; y: number } | null = null;
    const aim = (e: PointerEvent) => {
      const rect = element.getBoundingClientRect();
      raycaster.setFromCamera(
        new THREE.Vector2(
          ((e.clientX - rect.left) / rect.width) * 2 - 1,
          -((e.clientY - rect.top) / rect.height) * 2 + 1,
        ),
        camera,
      );
    };
    const move = (e: PointerEvent) => {
      aim(e);
      eyePlane.constant = -diorama.eyeHeight();
      diorama.lookAt(raycaster.ray.intersectPlane(eyePlane, new THREE.Vector3()));
      element.style.cursor = raycaster.intersectObject(diorama.catHitBox).length
        ? "pointer"
        : "grab";
    };
    const down = (e: PointerEvent) => (start = { x: e.clientX, y: e.clientY });
    const up = (e: PointerEvent) => {
      const moved = start ? Math.hypot(e.clientX - start.x, e.clientY - start.y) : 99;
      start = null;
      if (moved > 6) return;
      aim(e);
      if (!raycaster.intersectObject(diorama.catHitBox).length) return;
      diorama.purr();
      tapRef.current();
    };
    const leave = () => diorama.lookAt(null);
    element.addEventListener("pointermove", move);
    element.addEventListener("pointerdown", down);
    element.addEventListener("pointerup", up);
    element.addEventListener("pointerleave", leave);
    return () => {
      element.removeEventListener("pointermove", move);
      element.removeEventListener("pointerdown", down);
      element.removeEventListener("pointerup", up);
      element.removeEventListener("pointerleave", leave);
    };
  }, [gl, camera, diorama]);
}

/** A horizontal drag turns the room, like the app's DioramaView. Vertical drags stay page scrolls. */
function useDragToTurn(diorama: DioramaScene) {
  const { gl } = useThree();
  const dragging = useRef(false);
  useEffect(() => {
    const element = gl.domElement;
    let from: { x: number; yaw: number } | null = null;
    const down = (e: PointerEvent) => (from = { x: e.clientX, yaw: diorama.targetYaw });
    const move = (e: PointerEvent) => {
      if (!from) return;
      const dx = e.clientX - from.x;
      if (Math.abs(dx) < 6) return;
      dragging.current = true;
      diorama.setYaw(from.yaw + dx * 0.006);
    };
    const up = () => {
      from = null;
      setTimeout(() => (dragging.current = false), 1500);
    };
    element.addEventListener("pointerdown", down);
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
    return () => {
      element.removeEventListener("pointerdown", down);
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
  }, [gl, diorama]);
  return dragging;
}
