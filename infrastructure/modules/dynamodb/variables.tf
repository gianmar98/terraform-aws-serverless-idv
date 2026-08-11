# Copyright (c) 2026 Giancarlo Martinez
# SPDX-License-Identifier: Apache-2.0

# DynamoDB ---------------------------------------------------------------------------
variable "customer_metadata_dynamo_db_table_name" {
  description = "Name of the customer metadata DynamoDB table"
  type        = string
}

variable "customer_metadata_table_hash_partition_key" {
  description = "Hash/Partition key of the customer metadata table"
  type        = string
}

variable "customer_metadata_table_class" {
  description = "Storage class for the customer metadata DynamoDB table. Allowed: STANDARD, STANDARD_INFREQUENT_ACCESS."
  type        = string
  # default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.customer_metadata_table_class)
    error_message = "customer_metadata_table_class must be one of: STANDARD, STANDARD_INFREQUENT_ACCESS."
  }
}

variable "customer_metadata_table_RCU" {
  description = "Read Capacity Units for the customer metadata table"
  type        = number
  validation {
    condition     = var.customer_metadata_table_RCU >= 2
    error_message = "RCU must be at least 2"
  }
}

variable "customer_metadata_table_WCU" {
  description = "Write Capacity Units for the customer metadata table"
  type        = number
  validation {
    condition     = var.customer_metadata_table_WCU >= 2
    error_message = "WCU must be at least 2"
  }
}

variable "customer_metadata_table_pitr_enabled" {
  description = "Enable point-in-time recovery (continuous rolling backup) on the customer metadata table"
  type        = bool
}

variable "customer_metadata_table_deletion_protection" {
  description = "Block DeleteTable on the customer metadata table. When true, terraform destroy fails on this table until it is set back to false and applied."
  type        = bool
}

variable "customer_metadata_table_autoscaling_enabled" {
  description = "Enable autoscaling on the customer metadata table"
  type        = bool
}

variable "customer_metadata_table_min_RWcapacity" {
  description = "Minimum autoscaling capacity for the customer metadata table"
  type        = number
  validation {
    condition     = var.customer_metadata_table_min_RWcapacity >= 2
    error_message = "Min R/W capacity must be at least 2"
  }
}

variable "customer_metadata_table_max_RWcapacity" {
  description = "Maximum autoscaling capacity for the customer metadata table"
  type        = number
  validation {
    condition     = var.customer_metadata_table_max_RWcapacity <= 20
    error_message = "Max R/W capacity must be at most 20"
  }
}

variable "customer_metadata_table_target_scaling_val" {
  description = "Target % of provisioned capacity to trigger autoscaling"
  type        = number
  validation {
    condition     = var.customer_metadata_table_target_scaling_val >= 1 && var.customer_metadata_table_target_scaling_val <= 100
    error_message = "Target scaling value must be between 1 and 100."
  }
}