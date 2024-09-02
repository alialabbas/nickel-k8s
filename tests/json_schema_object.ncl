let { Records, .. } = import "../Contracts.ncl" in

{
  RecordWithPatternOnly =
    {
      third = "String",
      thrice = "3"
    }
      | Records.PatternMatcher
        ["!.*"]
        { "^th.*" = String },

  PatternAndContract =
    {
      first = 1,
      second = 2,
    }
      | { first | Number, second | Number }
      | Records.PatternMatcher
        [".*"]
        { "^th.*" = String },

  RecordWithOpenContract =
    {
      first = 1,
      second = 2,
      thrid = 3,
    }
      | { first | Number, second = 2, .. }
      | Records.PatternMatcher
        [".*"]
        { "^th.*" = String },

  RecordWithAdditionalPropertiesAndPattern =
    { first = 1, second = 2, third = "string" }
      | Records.PatternMatcher
        [".*"]
        { "^th.*" = String }
      | Records.PatternMatcher
        ["^th"]
        { ".*" = Number },
  RecordWithContractAndAdditionalAndPattern =
    {first = "1", third = "3", second = 2}
      | { first | String, .. }
      | Records.PatternMatcher
        [".*"]
        { "^th.*" = String }
      | Records.PatternMatcher
        ["^th", "^first$"]
        { ".*" = Number },
}
