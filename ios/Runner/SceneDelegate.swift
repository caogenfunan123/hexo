import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      guard let delegate = UIApplication.shared.delegate as? AppDelegate else { continue }
      delegate.handleFileURL(context.url)
    }
  }
}