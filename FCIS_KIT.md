# FCIS-KIT Declaration — ScoreKit

Declared under FCIS-KIT v1.0, requirement FCIS-KIT-01.

```yaml
FCIS-KIT:
  owns:
    - ScoreKit: domain-neutral notation, engraving, playback, MIDI 2.0 UMP, and semantic score model seams
    - ScoreKitUI: SwiftUI rendering and interaction projections for the score seam
  consumes:
    - kit: RulesKit-SPM
      mode: semver
      requirement: from "0.1.0"
    - kit: swift-openapi-urlsession
      mode: semver
      requirement: from "1.0.0"
  third-party-exceptions: []
```

ScoreKit does not own AudioTalk, Teatro, Reframe, product policy, manuscript data, credentials, or publication
decisions. Its MIDI 2.0 projection is software-side evidence only; it does not claim hardware interoperability.

## Release state

Current candidate source is `73c1f2d0926bbce57b872ffc5d948b2f2ecd3f40`. No semver release or GitHub release is claimed
until a clean-tree test run, annotated tag, release notes, and owning release decision satisfy FCIS-KIT-07.
