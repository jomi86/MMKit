import ActivityKit

public struct UVActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    public var uvIndex: Int
    public var recommendation: String
    public var riskLevelText: String
    public var spfIsActive: Bool
    public var spfFactor: Int?
    public var spfTimeRemaining: String?

    public init(
      uvIndex: Int,
      recommendation: String,
      riskLevelText: String,
      spfIsActive: Bool = false,
      spfFactor: Int? = nil,
      spfTimeRemaining: String? = nil
    ) {
      self.uvIndex = uvIndex
      self.recommendation = recommendation
      self.riskLevelText = riskLevelText
      self.spfIsActive = spfIsActive
      self.spfFactor = spfFactor
      self.spfTimeRemaining = spfTimeRemaining
    }
  }

  public var location: String

  public init(location: String) {
    self.location = location
  }
}
