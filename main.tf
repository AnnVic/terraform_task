provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "vpc-1" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = "true"

}

resource "aws_vpc" "vpc-2" {
  cidr_block           = "10.1.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = "true"
}

resource "aws_internet_gateway" "gate-1" {
  vpc_id = aws_vpc.vpc-1.id

}

resource "aws_internet_gateway" "gate-2" {
  vpc_id = aws_vpc.vpc-2.id
}

resource "aws_subnet" "vpc-1-subnet" {
  vpc_id                  = aws_vpc.vpc-1.id
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = "true"
}

resource "aws_subnet" "vpc-2-subnet" {
  vpc_id                  = aws_vpc.vpc-2.id
  cidr_block              = "10.1.0.0/24"
  map_public_ip_on_launch = "true"
}

resource "aws_route_table" "r1" {
  vpc_id = aws_vpc.vpc-1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gate-1.id
  }

}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.vpc-1-subnet.id
  route_table_id = aws_route_table.r1.id
}

resource "aws_vpc_peering_connection" "peer" {
  peer_vpc_id = aws_vpc.vpc-1.id
  vpc_id      = aws_vpc.vpc-2.id
  auto_accept = "true"
}

resource "aws_route_table" "r2" {
  vpc_id = aws_vpc.vpc-2.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gate-2.id
  }
}

resource "aws_route_table" "r3" {
  vpc_id = aws_vpc.vpc-2.id

  route {
    cidr_block = "10.0.0.0/24"
    gateway_id = aws_vpc_peering_connection.peer.id
  }
}

resource "aws_route_table_association" "c" {
  subnet_id      = aws_subnet.vpc-2-subnet.id
  route_table_id = aws_route_table.r3.id
}
resource "aws_instance" "instance-1" {
  ami                         = "ami-053b0d53c279acc90"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.vpc-1-subnet.id
  associate_public_ip_address = true

  tags = {
    Name = "AutoStop"
  }
}
resource "aws_instance" "instance-2" {
  ami                         = "ami-053b0d53c279acc90"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.vpc-2-subnet.id
  associate_public_ip_address = true

  tags = {
    Name = "AutoStop"
  }
}

resource "aws_db_instance" "default" {
  engine              = "postgres"
  allocated_storage   = 20
  engine_version      = "15.3"
  instance_class      = "db.t3.micro"
  username            = "foo"
  password            = "foobarbaz"
  skip_final_snapshot = true
}

resource "aws_lambda_function" "stop_instances_lambda" {
  filename      = "lambda_function.zip"
  function_name = "StopInstancesLambda"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.8"
  timeout       = 200
}

resource "aws_iam_role" "lambda_execution" {
  name = "LambdaExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  inline_policy {
    name = "lambda_execution_policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = "logs:*"
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action   = "ec2:*"
          Effect   = "Allow"
          Resource = "*"
        },

      ]
    })
  }
}

resource "aws_iam_policy_attachment" "lambda_execution_attachment" {
  name       = "LambdaExecutionPolicy"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  roles      = [aws_iam_role.lambda_execution.name]
}

resource "aws_cloudwatch_event_rule" "daily_schedule" {
  name                = "StopInstancesDailySchedule"
  description         = "Daily schedule to stop instances at 7 pm"
  schedule_expression = "cron(0 19 * * ? *)"
}

resource "aws_cloudwatch_event_target" "target" {
  rule = aws_cloudwatch_event_rule.daily_schedule.name
  arn  = aws_lambda_function.stop_instances_lambda.arn
}

resource "aws_lambda_permission" "cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_instances_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_schedule.arn
}
