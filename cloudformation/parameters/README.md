# Parameter files

Format = what `aws cloudformation deploy --parameter-overrides file://...` expects
with AWS CLI v2: a JSON **array of "Key=Value" strings** (NOT the
ParameterKey/ParameterValue object list — that older shape belongs to
`create-stack --parameters`). Mixing the two shapes is a common gotcha.

`AmiId` is the SSM **parameter name**, not an ami-... id — the template's
`AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>` type resolves it at deploy.
