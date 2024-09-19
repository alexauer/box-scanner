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

struct BoundingBox {
    var width: Float
    var height: Float
    var length: Float
}


class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    // MARK: - IBOutlets


    @IBOutlet weak var actionButton: UIButton!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var sessionInfoView: UIView!
    @IBOutlet weak var sceneView: ARSCNView!
    
    @IBOutlet weak var infoText: UITextField!
    var sessionState: ARSessionState = .notStarted
    // Collection to store ARPlaneAnchors with .none classification
    var noneClassifiedPlanes: [ARPlaneAnchor] = []
    
    // Bounding box
    var boundingBox: BoundingBox?
    var boundingBoxNode: SCNNode?
    
    // Endpoint URL (Replace with your actual endpoint)
    let endpointURL = URL(string: "http://192.168.178.109:8000/boxes/success1/size")!

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
        infoText.isHidden = false
        infoText.text = "Press Start Scan to begin"
        
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
        
        infoText.isHidden = true
        infoText.text = ""
        
        // Reset previous data
        noneClassifiedPlanes.removeAll()
        boundingBox = nil
        sendButton.isHidden = true
        boundingBoxNode?.removeFromParentNode()
        boundingBoxNode = nil


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
        stopPlaneDetection()
        calculateBoundingBox()

    }


    // MARK: - ARSCNViewDelegate
    
    /// - Tag: PlaceARContent
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // Place content only for anchors found by plane detection.
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        // Check if the plane has .none classification
        if #available(iOS 12.0, *), planeAnchor.classification == .none(.unknown) {
            // Store the plane anchor
            noneClassifiedPlanes.append(planeAnchor)
        }
        
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
        
        // Update the plane's visualization
        plane.update(anchor: planeAnchor)
        
        // If the plane's classification changed to .none(.unknown), add it to the collection
        if #available(iOS 12.0, *), planeAnchor.classification == .none(.unknown) {
            if !noneClassifiedPlanes.contains(where: { $0.identifier == planeAnchor.identifier }) {
                noneClassifiedPlanes.append(planeAnchor)
            }
        }
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
    
    // MARK: - Bounding Box Calculation
    
    private func calculateBoundingBox() {

        let plane1 = noneClassifiedPlanes[0]
        let plane2 = noneClassifiedPlanes[1]
        
        let h1 = plane1.planeExtent.height
        let w1 = plane1.planeExtent.width
        
        let h2 = plane2.planeExtent.height
        let w2 = plane2.planeExtent.width
        
        let d_min = min(abs(h1-h2), abs(h1-w2), abs(w1-h2), abs(w1-w2))
        
        var height: Float = 0
        var width: Float = 0
        var length: Float = 0
        
        if (abs(h1-h2) == d_min){
            height = h1
            width = w1
            length = w2
        } else if (abs(h1-w2) == d_min) {
            height = h1
            width = w1
            length = h2
        } else if (abs(w1-h2) == d_min) {
            height = h1
            width = w1
            length = w2
        } else if (abs(w1-w2) == d_min ){
            height = h1
            width = h2
            length = w2
        }

        // Sort height, width, and length from small to big
        let dimensions = [height, width, length].sorted()
        
        boundingBox = BoundingBox(width: dimensions[0], height: dimensions[1], length: dimensions[2])
        
        infoText.isHidden = false
        infoText.text = "W: \(dimensions[0]), H: \(dimensions[1]), L: \(dimensions[2])"
        sendButton.isHidden = false
        
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
            pauseARSession()
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
    @IBAction func sendButtonPressed(_ sender: Any) {
        if let box = boundingBox {
            sendBoxDimensions(box)
        } else {
            print("BoundingBox is nil")
        }
        sendButton.isEnabled = false
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
    
    private func sendBoxDimensions(_ box: BoundingBox) {
        
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prepare JSON payload
        let payload: [Float] = [
            box.width,
            box.height,
            box.length
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.httpBody = jsonData
        } catch {
            return
        }
        
        // Create data task
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            // Handle response on the main thread
            DispatchQueue.main.async {

                
                guard let httpResponse = response as? HTTPURLResponse else {
                    return
                }
                
                if (200...299).contains(httpResponse.statusCode) {
                    self.infoText.text = "Package size sent successfully"
                }else {
                    self.infoText.text = "Error sending"
                }
            }
        }
        
        task.resume()
    }
    
}


extension ARPlaneAnchor {
    /// Computes the four corner points of the plane in world coordinates.
    func cornerPoints() -> [SIMD3<Float>] {
        let center = self.center
        let extent = self.planeExtent
        let transform = self.transform
        
        // Local axes
        let right = SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
        let up = SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
        let normal = SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        
        // Half extents
        let halfWidth = extent.width / 2
        let halfLength = extent.height / 2
        
        // Assuming planes are either horizontal or vertical
        // Adjust corner calculations based on plane orientation
        let isHorizontal = abs(normal.y) > 0.9
        
        var corner1: SIMD3<Float>
        var corner2: SIMD3<Float>
        var corner3: SIMD3<Float>
        var corner4: SIMD3<Float>
        
        if isHorizontal {
            // Horizontal plane (floor/ceiling)
            corner1 = center + (-right * halfWidth) + (-up * halfLength)
            corner2 = center + (right * halfWidth) + (-up * halfLength)
            corner3 = center + (right * halfWidth) + (up * halfLength)
            corner4 = center + (-right * halfWidth) + (up * halfLength)
        } else {
            // Vertical plane (wall)
            corner1 = center + (-right * halfWidth) + (-up * halfLength)
            corner2 = center + (right * halfWidth) + (-up * halfLength)
            corner3 = center + (right * halfWidth) + (up * halfLength)
            corner4 = center + (-right * halfWidth) + (up * halfLength)
        }
        
        return [corner1, corner2, corner3, corner4]
    }
    
}
