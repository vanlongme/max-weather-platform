resource "null_resource" "delete_default_stage" {
  triggers = {
    api_id = aws_apigatewayv2_api.this.id
  }

  provisioner "local-exec" {
    command = "aws apigatewayv2 delete-stage --api-id ${self.triggers.api_id} --stage-name '$$default' 2>/dev/null || true"
  }

  depends_on = [
    aws_apigatewayv2_stage.this,
  ]
}
