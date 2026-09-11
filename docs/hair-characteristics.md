# Personal hair characteristics

The optional `characteristics` field on `HairLengthProfile` adds texture, visible flow and hairline observations. It is included in the profile hash, and therefore in every compiled brief and haircut's source identity. Existing profiles omit the field and retain their original encoding/hash after a decode/encode round trip.

Each characteristic carries observation origin, evidence quality, source hashes, method/version and capture conditions. A missing value must have unknown origin/quality. A known value cannot be a default and needs source references. These checks validate the record structure, not the contents or authenticity of external source evidence.

- Texture is regional: straight, wavy, curly, coily or mixed. Omitted regions remain unobserved.
- Flow uses unit tangents in the anatomical coordinate frame at a scalp binding. `visible_arrangement` describes the captured appearance. `estimated_root_growth` requires inferred or user-supplied provenance. The validator rejects a vector pointing out of the scalp or an observed label on estimated root growth.
- Hairline segments use ordered anchors on an exact scalp revision, with zero normal offset. Duplicate points and gaps over 5 cm fail validation. Missing segments remain unknown. Semantic placement, interpolation over curved topology and continuous hairline coverage still require validation.

The characteristic set is bound to a scalp hash, so it cannot silently move to different geometry. Input validation runs through both brief compilation and haircut validation. A changed characteristic/profile revision causes old haircut references to fail; it does not modify saved geometry.

The profile accepts an empty characteristic set or omitted regions without inventing coverage. Current bounds allow six texture regions, six hairline segments of at most 512 anchors each and 4,096 flow samples. These are processing limits, not sensor precision or coverage claims.

## Integration status

The existing `hair-brief` CLI accepts these fields in PROFILE.json and retains them in the compiled input. This is a data and validation path; automatic extraction, natural-hair capture alignment, user correction UI/history, density proxies, part curves and a generator that consumes these constraints remain unfinished. Existing complete-head and scalp inference limitations also remain.

Tests use synthetic scalp observations to verify persistence, source invalidation, absent-value semantics, legacy hash preservation, direction checks and hairline validation. They do not prove physical observation accuracy or personalized generation.
