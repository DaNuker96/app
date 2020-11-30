## Deploy ECS App ##

resource "aws_codebuild_project" "this" {
  name         = "main-codebuild"
  description  = "Codebuild for the aspnetapp on ECS"
  service_role = "${aws_iam_role.codebuild.arn}"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/docker:18.09.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "REPOSITORY_URI"
      value = "${aws_ecr_repository.main_ecr_repo.repository_url}"
    }

    environment_variable {
      name  = "NGINX_URI"
      value = "${aws_ecr_repository.nginx_ecr_repo.repository_url}" ##nginx repo uri environmental variable
    }

    environment_variable {
      name  = "TASK_DEFINITION"
      value = "arn:aws:ecs:${var.region}:${var.account_id}:task-definition/${aws_ecs_task_definition.main_task.family}"
    }

    environment_variable {
      name  = "SUBNET_1"
      value = "${aws_default_subnet.default_subnet_a.id}"
    }

    environment_variable {
      name  = "SUBNET_2"
      value = "${aws_default_subnet.default_subnet_b.id}"
    }

    environment_variable {
      name  = "SUBNET_3"
      value = "${aws_default_subnet.default_subnet_c.id}"
    }

    environment_variable {
      name  = "SECURITY_GROUP"
      value = "${aws_security_group.load_balancer_security_group.id}"
    }
  }

  source {
    type = "CODEPIPELINE"
  }
}

resource "aws_codedeploy_app" "this" {
  compute_platform = "ECS"
  name             = "aspnetapp"
}

## Deployment Groups ##

resource "aws_codedeploy_deployment_group" "this" {
  app_name               = "${aws_codedeploy_app.this.name}"
  deployment_group_name  = "aspnetapp-group"
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  service_role_arn       = "${aws_iam_role.codedeploy.arn}"

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action = "TERMINATE"
    }
  }

  ecs_service {
    cluster_name = "${aws_ecs_cluster.main_cluster.name}"
    service_name = "${aws_ecs_service.main_service.name}"
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = ["${aws_lb_listener.listener.arn}"]
      }

      target_group {
        name = "${aws_lb_target_group.target_group.*.name[0]}"
      }

      target_group {
        name = "${aws_lb_target_group.target_group.*.name[0]}"
      }
    }
  }
}

## Code Pipeline ##

resource "aws_codepipeline" "this" {
  name     = "main-pipeline"
  role_arn = "${aws_iam_role.pipeline.arn}"

  artifact_store {
    location = "${aws_s3_bucket.this.bucket}"
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source"]

      configuration = {
        OAuthToken = "${var.github_token}"
        Owner      = "DaNuker96"
        Repo       = "app"
        Branch     = "master"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source"]
      output_artifacts = ["build"]

      configuration = {
        ProjectName = "${aws_codebuild_project.this.name}"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["build"]

      configuration = {
        ApplicationName                = "${aws_codedeploy_app.this.name}"
        DeploymentGroupName            = "${aws_codedeploy_deployment_group.this.deployment_group_name}"
        TaskDefinitionTemplateArtifact = "build"
        AppSpecTemplateArtifact        = "build"
      }
    }
  }
}
