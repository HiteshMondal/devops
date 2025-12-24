resource "aws_db_instance" "main" {
  identifier           = "${var.project_name}-db"
  engine               = "postgres"
  engine_version       = "15.3"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  db_name              = "appdb"
  username             = "admin"
  password             = "changeme123"
  skip_final_snapshot  = true
  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.main.name

  tags = local.common_tags
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = local.common_tags
}