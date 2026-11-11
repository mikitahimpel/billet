// swift-format-ignore-file: AlwaysUseLowerCamelCase
#if !canImport(simd)
  // Linux has no simd module; these are the few calls the cat's geometry makes.
  package func simd_dot<V: SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar: FloatingPoint {
    (a * b).sum()
  }

  package func simd_length_squared<V: SIMD>(_ a: V) -> V.Scalar where V.Scalar: FloatingPoint {
    simd_dot(a, a)
  }

  package func simd_length<V: SIMD>(_ a: V) -> V.Scalar where V.Scalar: FloatingPoint {
    simd_length_squared(a).squareRoot()
  }

  package func simd_distance<V: SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar: FloatingPoint {
    simd_length(a - b)
  }

  package func simd_normalize<V: SIMD>(_ a: V) -> V where V.Scalar: FloatingPoint {
    a / V(repeating: simd_length(a))
  }
#endif
