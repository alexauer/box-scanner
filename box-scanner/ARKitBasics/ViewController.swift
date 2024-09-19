/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import UIKit
import SceneKit
import ARKit

enum ARSessionState {
    case notStarted
    case running
    case paused
}

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    // MARK: - IBOutlets


    @IBOutlet weak var actionButton: UIButton!
    @IBOutlet weak var sessionInfoView: UIView!
    @IBOutlet weak var sceneView: ARSCNView!
    
    var sessionState: ARSessionState = .notStarted

    // MARK: - View Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set a delegate to track the number of plane anchors for providing UI feedback.
        sceneView.session.delegate = self
        
        // Prevent the screen from being dimmed after a while as users will likely
        // have long periods of interaction without touching the screen or buttons.
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Show debug UI to view performance metrics (e.g. frames per second).
        sceneView.showsStatistics = true
        
        sceneView.preferredFramesPerSecond = 120
        sceneView.contentScaleFactor = 1.0
        
        actionButton.setTitle("Start Scan", for: .normal)
    }
        
    /// - Tag: StartARSession
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause the view's AR session.
        sceneView.session.pause()
    }
    
    // MARK: - SessionLifeCycle
    
    // Start the AR session
    private func startARSession() {

        // Start the view's AR session with a configuration that uses the rear camera,
        // device position and orientation tracking, and plane detection.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

    }
    
    private func pauseARSession() {
        // Pause the session but keep the detected planes visible
        sceneView.session.pause()
    }
    
    private func resumeARSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }

        // Resume the session without resetting tracking or removing anchors
        sceneView.session.run(configuration, options: [])
    }


    // MARK: - ARSCNViewDelegate
    
    /// - Tag: PlaceARContent
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // Place content only for anchors found by plane detection.
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        // Create a custom object to visualize the plane geometry and extent.
        let plane = Plane(anchor: planeAnchor, in: sceneView)
        
        // Add the visualization to the ARKit-managed node so that it tracks
        // changes in the plane anchor as plane estimation continues.
        node.addChildNode(plane)
    }

    /// - Tag: UpdateARContent
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // Update only anchors and nodes set up by `renderer(_:didAdd:for:)`.
        guard let planeAnchor = anchor as? ARPlaneAnchor,
            let plane = node.childNodes.first as? Plane
            else { return }
        
        // Update ARSCNPlaneGeometry to the anchor's new estimated shape.
        if let planeGeometry = plane.meshNode.geometry as? ARSCNPlaneGeometry {
            planeGeometry.update(from: planeAnchor.geometry)
        }

        // Update extent visualization to the anchor's new bounding rectangle.
        if let extentGeometry = plane.extentNode.geometry as? SCNPlane {
            extentGeometry.width = CGFloat(planeAnchor.planeExtent.width)
            extentGeometry.height = CGFloat(planeAnchor.planeExtent.height)
            plane.extentNode.simdPosition = planeAnchor.center
        }
        
        if let dimensionsNode = plane.classificationNode,
           let textGeometry = dimensionsNode.geometry as? SCNText {
            let newDimensionsText = getPlaneDimensionsText(anchor: planeAnchor)
            if let oldText = textGeometry.string as? String, oldText != newDimensionsText {
                textGeometry.string = newDimensionsText
                dimensionsNode.centerAlign()
            }
        }
        
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    }

    // MARK: - ARSessionObserver

    func sessionWasInterrupted(_ session: ARSession) {
        sessionState = .paused
        actionButton.setTitle("Restart", for: .normal)
        
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        resetTracking()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        
        sessionState = .notStarted
        actionButton.setTitle("Start", for: .normal)
        
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetTracking()
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    // MARK: - Button logic
    
    @IBAction func actionButtonPressed(_ sender: UIButton) {
        switch sessionState {
        case .notStarted:
            startARSession()
            sessionState = .running
            actionButton.setTitle("Stop Scan", for: .normal)
            actionButton.tintColor = UIColor.red
        case .running:
            stopPlaneDetection()
            sessionState = .paused
            actionButton.setTitle("Restart Scan", for: .normal)
            actionButton.tintColor = UIColor.gray
        case .paused:
            startARSession()
            sessionState = .running
            actionButton.setTitle("Stop Scan", for: .normal)
            actionButton.tintColor = UIColor.red
        }
    }
    
    func stopPlaneDetection() {
        // Get the current session configuration
        guard let currentConfiguration = sceneView.session.configuration as? ARWorldTrackingConfiguration else { return }

        // Disable plane detection
        currentConfiguration.planeDetection = []

        // Run the session with the updated configuration
        sceneView.session.run(currentConfiguration, options: [])
    }
    

    private func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
}
