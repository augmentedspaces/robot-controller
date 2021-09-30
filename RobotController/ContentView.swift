//
//  ContentView.swift
//  RobotController
//
//  Created by Nien Lam on 9/28/21.
//  Copyright © 2021 Line Break, LLC. All rights reserved.
//

import SwiftUI
import ARKit
import RealityKit
import Combine


// MARK: - View model for handling communication between the UI and ARView.
class ViewModel: ObservableObject {
    @Published var gameStatus: String = "START"

    @Published var robotIsWalking: Bool = false
    
    // For handling different button presses.
    enum UISignal {
        case resetAnchor
        case moveForward
        case rotateCCW
        case rotateCW
    }

    let uiSignal = PassthroughSubject<UISignal, Never>()
}


// MARK: - UI Layer.
struct ContentView : View {
    @StateObject var viewModel: ViewModel
    
    var body: some View {
        ZStack {
            // AR View.
            ARViewContainer(viewModel: viewModel)

            Text(viewModel.gameStatus)
                .font(.system(.largeTitle))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(40)

            // Reset button.
            Button {
                viewModel.uiSignal.send(.resetAnchor)
            } label: {
                Label("Reset", systemImage: "gobackward")
                    .font(.system(.title))
                    .foregroundColor(.white)
                    .labelStyle(IconOnlyLabelStyle())
                    .frame(width: 44, height: 44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
            
            // Controls.
            HStack {
                Button {
                    viewModel.uiSignal.send(.moveForward)
                } label: {
                    buttonIcon(viewModel.robotIsWalking ? "stop.fill" : "arrow.up", color: .blue)
                }
                
                Spacer()
                
                Button {
                    viewModel.uiSignal.send(.rotateCCW)
                } label: {
                    buttonIcon("rotate.left", color: .red)
                }
                
                Button {
                    viewModel.uiSignal.send(.rotateCW)
                } label: {
                    buttonIcon("rotate.right", color: .red)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 20)
            .padding(.vertical, 30)
        }
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
    }
    
    // Helper methods for rendering icon.
    func buttonIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .resizable()
            .padding(10)
            .frame(width: 44, height: 44)
            .foregroundColor(.white)
            .background(color)
            .cornerRadius(5)
    }
}


// MARK: - AR View.
struct ARViewContainer: UIViewRepresentable {
    let viewModel: ViewModel
    
    func makeUIView(context: Context) -> ARView {
        SimpleARView(frame: .zero, viewModel: viewModel)
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

class SimpleARView: ARView {
    var viewModel: ViewModel
    var arView: ARView { return self }
    var subscriptions = Set<AnyCancellable>()

    var planeAnchor: AnchorEntity?

    // Custom entities.
    var robotEntity: RobotEntity!
    var startPadEntity: PadEntity!
    var finishPadEntity: PadEntity!
    var blockEntity: BlockEntity!

    enum RobotState {
        case stop
        case walking
    }
    
    var robotState: RobotState = .stop {
        didSet {
            // This is called when robotState is updated.
            didUpdateRobotState()
        }
    }


    // TODO: Add additional game states.
    enum GameState {
        case start
    }
    
    var gameState: GameState = .start {
        didSet {
            // This is called when gameState is updated.
            didUpdateGameState()
        }
    }


    init(frame: CGRect, viewModel: ViewModel) {
        self.viewModel = viewModel
        super.init(frame: frame)
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        setupScene()
        
        setupEntities()
    }
        
    func setupScene() {
        // Setup world tracking and plane detection.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        arView.renderOptions = [.disableDepthOfField, .disableMotionBlur]
        arView.session.run(configuration)

        // Called every frame.
        scene.subscribe(to: SceneEvents.Update.self) { event in
            // Call renderLoop method on every frame.
            self.renderLoop()
        }.store(in: &subscriptions)

        // Process UI signals.
        viewModel.uiSignal.sink { [weak self] in
            self?.processUISignal($0)
        }.store(in: &subscriptions)
        
        // Respond to collision events.
        arView.scene.subscribe(to: CollisionEvents.Began.self) { event in
            // If entity with name block collides with anything.
            if event.entityA.name == "block" || event.entityB.name == "block" {
                self.didCollideWithBlock()
            }

            // If entity with name finishPad collides with anything.
            if event.entityA.name == "finishPad" || event.entityB.name == "finishPad" {
                self.didCollideWithFinishPad()
            }
        }.store(in: &subscriptions)


        //
        // Uncomment to show collision debug.
        // arView.debugOptions = [.showPhysics]
    }

    func processUISignal(_ signal: ViewModel.UISignal) {
        switch signal {
        case .resetAnchor:
            resetPlaneAnchor()
        case .moveForward:
            moveForwardPressed()
        case .rotateCCW:
            rotateCCWPressed()
        case .rotateCW:
            rotateCWPressed()
        }
    }

    // Create scene with custom classes.
    func setupEntities() {
        robotEntity     = RobotEntity(name: "mrRobot")
        startPadEntity  = PadEntity(name: "startPad", length: 0.15, color: UIColor.yellow)
        finishPadEntity = PadEntity(name: "finishPad", length: 0.15, color: UIColor.green)
        blockEntity     = BlockEntity(name: "block", size: 0.10, color: UIColor.red)
    }
    
    // Reset plane anchor and position entities.
    func resetPlaneAnchor() {
        planeAnchor?.removeFromParent()
        planeAnchor = nil
        
        planeAnchor = AnchorEntity(plane: [.horizontal])
        planeAnchor?.orientation = simd_quatf(angle: .pi / 2, axis: [0,1,0])
        arView.scene.addAnchor(planeAnchor!)
        
        planeAnchor!.addChild(robotEntity)

        planeAnchor!.addChild(startPadEntity)

        planeAnchor!.addChild(finishPadEntity)
        finishPadEntity.position.z = 1.0

        planeAnchor!.addChild(blockEntity)
        blockEntity.position.y = 0.05
        blockEntity.position.z = 0.5
    
        gameState = .start
    }
    

    func moveForwardPressed() {
        print("👇 Did press move forward")

        if robotState == .stop {
            robotState = .walking
        } else if robotState == .walking {
            robotState = .stop
        }
    }


    // TODO: Implement control to rotate CCW.
    func rotateCCWPressed() {
        print("👇 Did press rotate CCW")

    }


    // TODO: Implement control to rotate CW.
    func rotateCWPressed() {
        print("👇 Did press rotate CW")

    }


    // TODO: Respond to robot state changes.
    func didUpdateRobotState() {
        switch robotState {
        case .stop:
            print("🤖 robotState: stop")
            robotEntity.animate(false)
            viewModel.robotIsWalking = false

        case .walking:
            print("🤖 robotState: walking")
            robotEntity.animate(true)
            viewModel.robotIsWalking = true
        }
    }
    

    // TODO: Respond to game state changes.
    func didUpdateGameState() {
        switch gameState {
        case .start:
            print("➡️ gameState: start")
            viewModel.gameStatus = "START"
            
            robotState = .stop
            robotEntity.position = [0,0,0]
        }
    }


    // TODO: Respond to block collision.
    func didCollideWithBlock() {
        print("💥 Colliding with Block")

    }
    

    // TODO: Respond to finish pad collision.
    func didCollideWithFinishPad() {
        print("💥 Colliding with Finish pad")

    }
    
    
    // TODO: Move robot forward based on robotState variable.
    func renderLoop() {

    }
}


// Classes for custom entities.
// IMPORTANT: Collision shapes are autogenerated for detection.

// MARK: - Robot Entity with start/stop animation methods
class RobotEntity: Entity {
    let model: Entity

    init(name: String) {
        model = try! Entity.load(named: "toy_robot_vintage")
        model.name = name
        model.generateCollisionShapes(recursive: true)

        super.init()

        self.addChild(model)
    }
    
    required init() {
        fatalError("init() has not been implemented")
    }

    // Play or stop animation.
    func animate(_ animate: Bool) {
        if animate {
            if let animation = model.availableAnimations.first {
                model.playAnimation(animation.repeat())
            }
        } else {
            model.stopAllAnimations()
        }
    }
}


// MARK: - Pad Entity
class PadEntity: Entity {
    let model: ModelEntity
    
    init(name: String, length: Float, color: UIColor) {
        let material = SimpleMaterial(color: color, isMetallic: false)
        model = ModelEntity(mesh: .generateBox(size: [length, 0.001, length]), materials: [material])
        model.name = name

        model.generateCollisionShapes(recursive: true)

        super.init()

        self.addChild(model)
    }
    
    required init() {
        fatalError("init() has not been implemented")
    }
}


// MARK: - Block Entity
class BlockEntity: Entity {
    let model: ModelEntity
    
    init(name: String, size: Float, color: UIColor) {
        let material = SimpleMaterial(color: color, isMetallic: false)
        model = ModelEntity(mesh: .generateBox(size: size, cornerRadius: 0.002), materials: [material])
        model.name = name
        model.generateCollisionShapes(recursive: true)

        super.init()

        self.addChild(model)
    }
    
    required init() {
        fatalError("init() has not been implemented")
    }
}
