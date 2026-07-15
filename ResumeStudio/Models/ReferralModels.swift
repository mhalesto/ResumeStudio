import Foundation

struct ReferralProfile: Codable, Equatable {
  struct Rewards: Codable, Equatable {
    var newUser: Int
    var owner: Int
  }

  struct Limits: Codable, Equatable {
    var perDay: Int
    var rolling: Int
    var windowDays: Int
  }

  var code: String
  var shareURL: URL
  var successfulReferrals: Int
  var remainingToday: Int
  var remainingInWindow: Int
  var bonusCredits: Int
  var rewards: Rewards
  var limits: Limits
}

struct ReferralRedemption: Codable, Equatable {
  var message: String
  var creditsAwarded: Int
}
