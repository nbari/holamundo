provider "aws" {
  region = "us-east-1"
}

data "aws_s3_bucket" "existing_terraform_state" {
  bucket = "tf-state-bucket-lyama"
}

data "aws_dynamodb_table" "existing_terraform_lock" {
  name = "tf-lock-table"
}

resource "aws_s3_bucket" "terraform_state" {
  count = length(data.aws_s3_bucket.existing_terraform_state) == 0 ? 1 : 0
  
  bucket = "tf-state-bucket-lyama"  
}

resource "aws_dynamodb_table" "terraform_lock" {
  count = length(data.aws_dynamodb_table.existing_terraform_lock) == 0 ? 1 : 0

  name           = "tf-lock-table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

terraform {
  backend "s3" {
    bucket         = "tf-state-bucket-lyama"
    key            = "01/terraform.tfstate"
    region         = "us-east-1"
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "subnet1" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "subnet2" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.main.id
}

resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_security_group" "allow_http" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_ecr_repository" "existing_holamundo" {
  name = "holamundo"
}

resource "aws_ecr_repository" "holamundo" {
  count = length(data.aws_ecr_repository.existing_holamundo.repository_url) == 0 ? 1 : 0

  name = "holamundo"

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_ecs_cluster" "main" {
  name = "hello-world-cluster"
}

resource "aws_ecs_task_definition" "hello_world" {
  family                   = "hello-world-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "hello-world"
      image     = length(data.aws_ecr_repository.existing_holamundo.repository_url) > 0 ? "${data.aws_ecr_repository.existing_holamundo.repository_url}:latest" : "${aws_ecr_repository.holamundo[0].repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "hello_world" {
  name            = "hello-world-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.hello_world.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
    security_groups  = [aws_security_group.allow_http.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "hello-world"
    container_port   = 80
  }
  depends_on = [
    aws_lb_listener.main
  ]
}

resource "aws_lb" "main" {
  name               = "hello-world-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http.id]
  subnets            = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
}

resource "aws_lb_target_group" "main" {
  name     = "hello-world-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# Output para obtener el DNS del Load Balancer
output "lb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}
