// The photos are UIKit images: the target compiles to nothing for the package's macOS tests.
#if canImport(UIKit)
  import CoreImage
  import CoreImage.CIFilterBuiltins
  import UIKit

  /// The light instant-film grade every polaroid gets when it is drawn: lifted, warm blacks, creamy highlights, a little
  /// less contrast and saturation, and a faint vignette. The stored JPEG is never changed. Safe off the main thread.
  public enum InstantFilm {
    public static func develop(_ image: UIImage) -> UIImage? {
      guard let cg = image.cgImage else { return nil }
      let input = CIImage(cgImage: cg)

      let tone = CIFilter.colorControls()
      tone.inputImage = input
      tone.saturation = 0.9
      tone.contrast = 0.93

      // Gains pull the blue down and the red up so whites turn cream; the bias lifts black to a warm brown.
      let warm = CIFilter.colorMatrix()
      warm.inputImage = tone.outputImage
      warm.rVector = CIVector(x: 1.0, y: 0.02, z: 0, w: 0)
      warm.gVector = CIVector(x: 0, y: 0.97, z: 0, w: 0)
      warm.bVector = CIVector(x: 0, y: 0, z: 0.88, w: 0)
      warm.biasVector = CIVector(x: 0.06, y: 0.045, z: 0.035, w: 0)

      let vignette = CIFilter.vignette()
      vignette.inputImage = warm.outputImage
      vignette.intensity = 0.4
      vignette.radius = 1.6

      guard let output = vignette.outputImage?.cropped(to: input.extent),
        let graded = context.createCGImage(output, from: input.extent)
      else { return nil }
      return UIImage(cgImage: graded, scale: image.scale, orientation: image.imageOrientation)
    }

    /// CIContext is thread-safe and costly to make, so one serves every print.
    private static let context = CIContext(options: [.cacheIntermediates: false])
  }
#endif
