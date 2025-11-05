variable "bucketname" {
  default = "staticwebsiterraform-ja"
}

variable "cidr" {
  default = "10.0.0.0/16"
}

variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type = string
}