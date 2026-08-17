output "document_state_machine_name" {
  description = "Name of the Step Functions state machine that orchestrates the document pipeline"
  value       = aws_sfn_state_machine.document_state_machine.name
}

output "document_state_machine_arn" {
  description = "ARN of the Step Functions state machine that orchestrates the document pipeline"
  value       = aws_sfn_state_machine.document_state_machine.arn
}
