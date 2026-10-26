import AppKit
import Metal
import SceneKit
import simd

// Rebuild the authored connection turntables on macOS (requires a Metal-capable session):
// swiftc scripts/generate-airpods-artwork.swift -o /tmp/generate-airpods-artwork
// /tmp/generate-airpods-artwork [NotchiumPackage/Sources/NotchiumDynamicIsland/Resources]
// Each transparent PNG is 61 left-to-right 96 × 96 frames, yaw −360° ... 0° inclusive.
// The geometry below is original, approximate product illustration, with no imported assets.

private let frameSize = 96
private let frameCount = 61
private let renderScale = 4
private let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
    ?? "NotchiumPackage/Sources/NotchiumDynamicIsland/Resources", isDirectory: true)

private enum Product: String, CaseIterable {
    case airPods = "AirPodsTurn"
    case airPodsPro = "AirPodsProTurn"
    case airPodsMax = "AirPodsMaxTurn"
}

private func material(_ color: NSColor, metal: CGFloat = 0, roughness: CGFloat = 0.28) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    material.diffuse.contents = color
    material.metalness.contents = metal
    material.roughness.contents = roughness
    material.isDoubleSided = true
    return material
}

private let porcelain = material(NSColor(white: 0.74, alpha: 1), roughness: 0.3)
private let silicone = material(NSColor(white: 0.84, alpha: 1), roughness: 0.72)
private let vent = material(NSColor(white: 0.035, alpha: 1), roughness: 0.82)
private let chrome = material(NSColor(white: 0.68, alpha: 1), metal: 0.86, roughness: 0.22)
private let aluminum = material(NSColor(white: 0.78, alpha: 1), metal: 0.7, roughness: 0.4)
private let cushion = material(NSColor(white: 0.11, alpha: 1), roughness: 0.94)
private let mesh = material(NSColor(white: 0.2, alpha: 1), roughness: 0.95)

@discardableResult
private func ellipsoid(_ parent: SCNNode, at position: SIMD3<Float>, size: SIMD3<Float>,
                       material: SCNMaterial) -> SCNNode {
    let geometry = SCNSphere(radius: 1)
    geometry.segmentCount = 56
    geometry.firstMaterial = material
    let node = SCNNode(geometry: geometry)
    node.simdPosition = position
    node.simdScale = size
    parent.addChildNode(node)
    return node
}

@discardableResult
private func capsule(_ parent: SCNNode, from start: SIMD3<Float>, to end: SIMD3<Float>, radius: Float,
                     material: SCNMaterial) -> SCNNode {
    let geometry = SCNCapsule(capRadius: CGFloat(radius), height: CGFloat(simd_distance(start, end) + 2 * radius))
    geometry.radialSegmentCount = 40
    geometry.capSegmentCount = 12
    geometry.firstMaterial = material
    let node = SCNNode(geometry: geometry)
    node.simdPosition = (start + end) / 2
    node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(end - start))
    parent.addChildNode(node)
    return node
}

private func classicBud(side: Float) -> SCNNode {
    let bud = SCNNode()
    // Straight stems and an organic, asymmetric speaker body form the familiar earbud silhouette.
    capsule(bud, from: [0, -0.47, 0], to: [0, 0.15, 0], radius: 0.076, material: porcelain)
    ellipsoid(bud, at: [-side * 0.036, 0.29, 0.006], size: [0.18, 0.222, 0.17], material: porcelain)
    ellipsoid(bud, at: [-side * 0.135, 0.31, 0.08], size: [0.143, 0.17, 0.143], material: porcelain)
    let speaker = ellipsoid(bud, at: [-side * 0.215, 0.326, 0.147],
                            size: [0.037, 0.112, 0.078], material: vent)
    speaker.eulerAngles.y = CGFloat(-side * 0.42)
    let outerVent = ellipsoid(bud, at: [side * 0.032, 0.355, 0.165],
                              size: [0.048, 0.068, 0.011], material: vent)
    outerVent.eulerAngles.z = CGFloat(side * 0.12)
    // Rear pressure port remains visible during the back half of the orbit.
    ellipsoid(bud, at: [side * 0.028, 0.32, -0.16], size: [0.032, 0.052, 0.012], material: vent)
    capsule(bud, from: [0, -0.483, 0], to: [0, -0.471, 0], radius: 0.073, material: chrome)
    ellipsoid(bud, at: [0, -0.516, 0.06], size: [0.029, 0.013, 0.012], material: vent)
    bud.simdPosition = [side * 0.4, 0.06, 0]
    return bud
}

private func proBud(side: Float) -> SCNNode {
    let bud = SCNNode()
    capsule(bud, from: [side * 0.006, -0.4, -0.025], to: [0, 0.11, 0], radius: 0.086, material: porcelain)
    let body = ellipsoid(bud, at: [side * 0.015, 0.245, 0],
                         size: [0.213, 0.26, 0.195], material: porcelain)
    body.eulerAngles.z = CGFloat(-side * 0.55)
    ellipsoid(bud, at: [-side * 0.095, 0.175, 0.055], size: [0.16, 0.16, 0.16], material: porcelain)
    // The silicone nozzle points inward, slightly down and forward; its speaker is inset
    // into the tip's end rather than painted on a flat silhouette.
    let nozzleDirection = simd_normalize(SIMD3<Float>(-side * 0.75, -0.25, 0.61))
    let nozzleCenter = SIMD3<Float>(-side * 0.175, 0.14, 0.085)
    let tipGeometry = SCNCone(topRadius: 0.088, bottomRadius: 0.122, height: 0.18)
    tipGeometry.radialSegmentCount = 48
    tipGeometry.firstMaterial = silicone
    let tip = SCNNode(geometry: tipGeometry)
    tip.simdPosition = nozzleCenter + nozzleDirection * 0.035
    tip.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: nozzleDirection)
    bud.addChildNode(tip)
    let lipGeometry = SCNTorus(ringRadius: 0.076, pipeRadius: 0.016)
    lipGeometry.ringSegmentCount = 48
    lipGeometry.pipeSegmentCount = 16
    lipGeometry.firstMaterial = silicone
    let lip = SCNNode(geometry: lipGeometry)
    lip.simdPosition = nozzleCenter + nozzleDirection * 0.125
    lip.simdOrientation = tip.simdOrientation
    bud.addChildNode(lip)
    let speaker = ellipsoid(bud, at: nozzleCenter + nozzleDirection * 0.126,
                            size: [0.058, 0.058, 0.006], material: vent)
    speaker.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: nozzleDirection)
    let outerVent = ellipsoid(bud, at: [side * 0.071, 0.352, 0.166],
                              size: [0.035, 0.077, 0.014], material: vent)
    outerVent.eulerAngles.z = CGFloat(-side * 0.9)
    ellipsoid(bud, at: [side * 0.083, 0.23, -0.172], size: [0.044, 0.075, 0.016], material: vent)
    // Flat force sensor and small stem microphone, kept subtle at the final 24 pt display size.
    ellipsoid(bud, at: [0.009, -0.15, 0.073], size: [0.037, 0.13, 0.014], material: silicone)
    capsule(bud, from: [side * 0.006, -0.418, -0.025], to: [side * 0.006, -0.403, -0.025],
            radius: 0.082, material: chrome)
    ellipsoid(bud, at: [0.005, -0.44, 0.045], size: [0.03, 0.012, 0.013], material: vent)
    bud.simdPosition = [side * 0.43, -0.025, 0]
    return bud
}

@discardableResult
private func roundedCup(_ parent: SCNNode, at position: SIMD3<Float>, width: CGFloat, height: CGFloat,
                        depth: CGFloat, corner: CGFloat, material: SCNMaterial) -> SCNNode {
    let path = NSBezierPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                            xRadius: corner, yRadius: corner)
    path.flatness = 0.005
    let geometry = SCNShape(path: path, extrusionDepth: depth)
    geometry.chamferRadius = min(depth * 0.3, 0.04)
    geometry.firstMaterial = material
    let node = SCNNode(geometry: geometry)
    node.simdPosition = position
    parent.addChildNode(node)
    return node
}

private func maxHeadphones() -> SCNNode {
    let headphones = SCNNode()
    // A mesh canopy, two stainless rails and telescoping arms form the open arch silhouette.
    let steps = 48
    func arch(_ t: Float, z: Float) -> SIMD3<Float> {
        [-0.48 * cos(t), 0.12 + 0.67 * sin(t), z]
    }
    for index in 0..<steps {
        let a = Float(index) * .pi / Float(steps)
        let b = Float(index + 1) * .pi / Float(steps)
        capsule(headphones, from: arch(a, z: -0.077), to: arch(b, z: -0.077), radius: 0.025, material: chrome)
        capsule(headphones, from: arch(a, z: 0.077), to: arch(b, z: 0.077), radius: 0.025, material: chrome)
        capsule(headphones, from: arch(a, z: 0), to: arch(b, z: 0), radius: 0.067, material: mesh)
        // Woven transverse fibers make the canopy readable when it turns overhead.
        if index % 2 == 0 {
            capsule(headphones, from: arch(a, z: -0.065) + [0, 0.025, 0],
                    to: arch(a, z: 0.065) + [0, 0.025, 0], radius: 0.007, material: cushion)
        }
    }
    for side: Float in [-1, 1] {
        capsule(headphones, from: [side * 0.48, 0.19, 0], to: [side * 0.48, -0.155, 0],
                radius: 0.029, material: chrome)
        let cup = SCNNode()
        roundedCup(cup, at: [0, 0, -0.09], width: 0.43, height: 0.625, depth: 0.15,
                   corner: 0.18, material: cushion)
        roundedCup(cup, at: [0, 0, 0.015], width: 0.455, height: 0.67, depth: 0.18,
                   corner: 0.195, material: aluminum)
        // The outward shell has a separate shallow surface, giving the aluminum a softer edge.
        roundedCup(cup, at: [0, 0, 0.115], width: 0.423, height: 0.63, depth: 0.035,
                   corner: 0.183, material: aluminum)
        cup.simdPosition = [side * 0.455, -0.24, 0]
        cup.eulerAngles.y = CGFloat(side * 0.9)
        cup.eulerAngles.z = CGFloat(-side * 0.35)
        headphones.addChildNode(cup)
        if side > 0 {
            capsule(cup, from: [0.09, 0.33, 0.055], to: [0.09, 0.35, 0.055], radius: 0.032, material: chrome)
            capsule(cup, from: [-0.075, 0.335, 0.035], to: [-0.03, 0.335, 0.035], radius: 0.012, material: chrome)
        }
    }
    headphones.simdPosition.y = -0.07
    return headphones
}

private func makeProduct(_ product: Product) -> SCNNode {
    let root = SCNNode()
    switch product {
    case .airPods:
        root.addChildNode(classicBud(side: -1))
        root.addChildNode(classicBud(side: 1))
    case .airPodsPro:
        root.addChildNode(proBud(side: -1))
        root.addChildNode(proBud(side: 1))
    case .airPodsMax:
        root.addChildNode(maxHeadphones())
    }
    return root
}

private func addLight(_ scene: SCNScene, type: SCNLight.LightType, position: SCNVector3,
                      intensity: CGFloat, color: NSColor = .white) {
    let node = SCNNode()
    node.light = SCNLight()
    node.light?.type = type
    node.light?.intensity = intensity
    node.light?.color = color
    node.position = position
    scene.rootNode.addChildNode(node)
}

private func writeStrip(_ product: Product, renderer: SCNRenderer) throws {
    let scene = SCNScene()
    scene.background.contents = NSColor.clear
    let model = makeProduct(product)
    scene.rootNode.addChildNode(model)
    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera?.usesOrthographicProjection = true
    camera.camera?.orthographicScale = product == .airPodsMax ? 0.96 : 0.87
    camera.camera?.zNear = 0.1
    camera.camera?.zFar = 20
    camera.camera?.wantsHDR = false
    camera.position = SCNVector3(0, 0, 5)
    scene.rootNode.addChildNode(camera)
    addLight(scene, type: .ambient, position: SCNVector3Zero, intensity: 65)
    addLight(scene, type: .omni, position: SCNVector3(-3, 4, 5), intensity: 330)
    addLight(scene, type: .omni, position: SCNVector3(4, 0.5, 3), intensity: 95)
    addLight(scene, type: .omni, position: SCNVector3(0, 3, -4), intensity: 260)
    renderer.scene = scene
    renderer.pointOfView = camera
    let width = frameSize * frameCount
    guard let context = CGContext(data: nil, width: width, height: frameSize, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CocoaError(.coderInvalidValue)
    }
    context.interpolationQuality = .high
    for frame in 0..<frameCount {
        // frame 0 and 60 share exactly the same front pose, avoiding a wrap seam.
        let degrees = frame == 0 ? 0 : -360 + Double(frame) * 6
        model.eulerAngles.y = CGFloat(degrees * .pi / 180)
        let snapshot = renderer.snapshot(atTime: 0,
            with: NSSize(width: frameSize * renderScale, height: frameSize * renderScale),
            antialiasingMode: .multisampling4X)
        guard let image = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "AirPodsArtwork", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "SceneKit produced an empty image; run in a Metal-capable macOS session."])
        }
        context.draw(image, in: CGRect(x: frame * frameSize, y: 0, width: frameSize, height: frameSize))
    }
    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let path = output.appendingPathComponent(product.rawValue + ".png")
    try png.write(to: path, options: .atomic)
    print("\(path.path): \(width) × \(frameSize), \(frameCount) transparent frames")
}

guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("A Metal-capable macOS session is required for the offscreen SceneKit artwork renderer.")
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let renderer = SCNRenderer(device: device, options: nil)
renderer.autoenablesDefaultLighting = false
for product in Product.allCases {
    try autoreleasepool { try writeStrip(product, renderer: renderer) }
}
