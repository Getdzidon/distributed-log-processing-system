variable "table_name" {
  type = string
}

variable "enable_global_table" {
  type = bool
}

variable "replica_regions" {
  type = list(string)
}

variable "environment" {
  type = string
}
