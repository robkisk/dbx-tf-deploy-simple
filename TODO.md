# TODO: Workspace Asset Deployment Enhancements

## Overview
This TODO list focuses on rapidly deploying code examples and assets from Git repositories directly to the Databricks workspace. The goal is to create a complete demo environment that provisions both infrastructure and ready-to-use workspace content.

### Serverless-First Approach
**All compute resources in this project use serverless by default:**
- ✅ **Notebooks** - Run on serverless compute (no cluster management)
- ✅ **Jobs** - Execute with serverless compute (instant startup)
- ✅ **SQL Warehouses** - Use serverless SQL endpoints (auto-scaling)
- ✅ **Delta Live Tables** - Leverage serverless pipelines when available

**Benefits**: Zero cluster management, instant startup, pay-per-use pricing, automatic scaling, and optimal cost efficiency.

---

## Phase 1: Git Repository Integration (HIGH PRIORITY)

### 1.1 Add Databricks Repos Resource
**Goal**: Connect a Git repository to deploy notebooks and code directly to the workspace

**Implementation**:
- [ ] Add `databricks_repo` resource to `main.tf`
- [ ] Configure to clone from a public Git repository (or your own demo repo)
- [ ] Set default branch to `main` or `master`
- [ ] Place repo in `/Repos/demos/` or `/Workspace/Repos/` path

**Example Pattern**:
```hcl
resource "databricks_repo" "demo_repo" {
  url  = "https://github.com/<org>/<repo>"
  path = "/Repos/demos/getting-started"
}
```

**Benefits**: Instant code deployment, version control integration, easy updates

---

### 1.2 Support Multiple Repository Sources
**Goal**: Allow deployment of various example repositories

**Implementation**:
- [ ] Create variable `demo_repositories` as a map of repo configurations
- [ ] Use `for_each` to deploy multiple repos simultaneously
- [ ] Include popular Databricks example repos (databricks/tech-talks, databricks-demos, etc.)

**Suggested Repos**:
- Databricks Academy materials
- Delta Lake examples
- MLflow tutorials
- Spark SQL demos

---

## Phase 2: Workspace Resources (HIGH PRIORITY)

### 2.1 Deploy Sample Notebooks
**Goal**: Provide ready-to-run notebook examples in the workspace

**Implementation**:
- [ ] Create `notebooks/` directory in project
- [ ] Add 3-5 example notebooks:
  - `01_getting_started.py` - Basic Spark operations
  - `02_delta_lake_intro.sql` - Delta table operations
  - `03_data_analysis.py` - Pandas/DataFrame examples
  - `04_unity_catalog.sql` - UC catalog/schema operations
  - `05_ml_quickstart.py` - Simple ML example with MLflow
- [ ] Use `databricks_notebook` resource to deploy each notebook
- [ ] Place in `/Shared/demo-notebooks/` path

**Example Pattern**:
```hcl
resource "databricks_notebook" "getting_started" {
  source   = "${path.module}/notebooks/01_getting_started.py"
  path     = "/Shared/demo-notebooks/01_getting_started"
  language = "PYTHON"
}
```

---

### 2.2 Enable Serverless Compute
**Goal**: Configure workspace to use serverless compute for all workloads

**Implementation**:
- [ ] Enable serverless compute at workspace level
- [ ] Configure notebooks to use serverless by default
- [ ] Set up cluster policies that enforce serverless usage
- [ ] Document serverless capabilities (instant startup, auto-scaling, no cluster management)

**Important Notes**:
- **No traditional clusters needed** - Serverless provides instant compute
- **Cost-effective** - Pay only for actual compute time, no idle clusters
- **Zero management** - No node types, worker counts, or Spark versions to configure
- **Automatic optimization** - Databricks handles all scaling and resource allocation

**Example Notebook Configuration**:
```python
# Notebooks automatically use serverless when enabled
# No cluster attachment needed - just run the notebook

# In Python notebooks, serverless is the default execution environment
df = spark.read.table("samples.nyctaxi.trips")
display(df)
```

**Serverless Configuration for Jobs**:
```hcl
# Jobs use serverless by default when available
resource "databricks_job" "serverless_job" {
  name = "Serverless Demo Job"

  task {
    task_key = "serverless_task"

    # No cluster configuration needed
    # Serverless is automatic

    notebook_task {
      notebook_path = databricks_notebook.getting_started.path
    }
  }

  # Optional: Control serverless settings
  compute {
    compute_type = "serverless"
  }
}
```

---

### 2.3 Deploy Automated Jobs with Serverless
**Goal**: Demonstrate job orchestration using serverless compute

**Implementation**:
- [ ] Create 2-3 example serverless jobs:
  - Daily data processing job (runs a notebook on serverless)
  - Multi-task workflow (notebook → notebook → SQL on serverless)
  - Scheduled report generation with serverless SQL
- [ ] Use `databricks_job` resource with serverless compute configuration
- [ ] Configure email notifications for job completion
- [ ] Set schedules using cron expressions
- [ ] All jobs use serverless - no cluster management required

**Example Serverless Job Patterns**:

```hcl
# Simple notebook job with serverless
resource "databricks_job" "daily_processing" {
  name = "Daily Data Processing (Serverless)"

  schedule {
    quartz_cron_expression = "0 0 1 * * ?"  # Daily at 1 AM
    timezone_id            = "America/Los_Angeles"
  }

  task {
    task_key = "process_data"

    notebook_task {
      notebook_path = "/Shared/demo-notebooks/02_delta_lake_intro"
    }

    # Serverless compute - no cluster needed
  }

  email_notifications {
    on_success = ["demo@example.com"]
    on_failure = ["demo@example.com"]
  }
}

# Multi-task DAG workflow with serverless
resource "databricks_job" "multi_task_workflow" {
  name = "Multi-Task Workflow (Serverless)"

  task {
    task_key = "bronze_ingestion"

    notebook_task {
      notebook_path = "/Shared/demo-notebooks/01_ingest_data"
    }
  }

  task {
    task_key = "silver_transformation"

    depends_on {
      task_key = "bronze_ingestion"
    }

    notebook_task {
      notebook_path = "/Shared/demo-notebooks/02_transform_data"
    }
  }

  task {
    task_key = "gold_aggregation"

    depends_on {
      task_key = "silver_transformation"
    }

    sql_task {
      warehouse_id = databricks_sql_endpoint.serverless.id
      query {
        query_id = databricks_query.aggregation.id
      }
    }
  }
}
```

**Benefits of Serverless Jobs**:
- Instant startup (no cluster provisioning wait)
- Auto-scaling based on workload
- Cost optimization (pay per use)
- Zero cluster management overhead

---

## Phase 3: Unity Catalog Objects (MEDIUM PRIORITY)

### 3.1 Create Sample Catalog Structure
**Goal**: Provide a complete Unity Catalog hierarchy for demos

**Implementation**:
- [ ] Add variables for metastore ID (if using existing) or create new metastore
- [ ] Create `databricks_metastore_assignment` to link workspace
- [ ] Create storage credential using the access connector
- [ ] Create external location pointing to ADLS container
- [ ] Create demo catalog: `demo_catalog`
- [ ] Create schemas within catalog: `bronze`, `silver`, `gold`, `samples`
- [ ] Add volume for unstructured data

**Resources Needed**:
```hcl
# Storage credential, external location, catalog, schemas, volumes
```

**Pattern**: Follow Medallion Architecture (bronze/silver/gold)

---

### 3.2 Deploy Sample Tables
**Goal**: Pre-populate workspace with sample data tables

**Implementation**:
- [ ] Create `databricks_sql_table` resources for sample data
- [ ] Use Databricks sample datasets (diamonds, iris, nyctaxi)
- [ ] Create Delta tables in appropriate schemas
- [ ] Add table comments and column descriptions
- [ ] Set table properties for optimization

**Sample Tables**:
- `demo_catalog.samples.diamonds` - Classic dataset
- `demo_catalog.samples.customer_data` - Synthetic customer data
- `demo_catalog.samples.sales_transactions` - Synthetic sales data

---

### 3.3 Configure Permissions and Grants
**Goal**: Set up appropriate access controls on UC objects

**Implementation**:
- [ ] Use `databricks_grants` resource
- [ ] Grant `USE CATALOG` and `USE SCHEMA` to `account users`
- [ ] Grant `SELECT` on sample tables to all users
- [ ] Grant `CREATE TABLE` on schemas to specific groups
- [ ] Document permission model in comments

---

## Phase 4: Sample Data & Datasets (MEDIUM PRIORITY)

### 4.1 Upload Sample Data Files
**Goal**: Provide CSV/JSON/Parquet files for demos

**Implementation**:
- [ ] Create `sample_data/` directory in project
- [ ] Add 3-5 sample datasets (CSV, JSON, Parquet formats)
- [ ] Use `azurerm_storage_blob` to upload to storage account
- [ ] Create container specifically for demo data
- [ ] Document data schemas in README or data dictionary

**Sample Datasets**:
- `customers.csv` - Customer demographics (100-1000 rows)
- `products.json` - Product catalog
- `transactions.parquet` - Sales transactions
- `sensor_data.csv` - IoT/time-series data

---

### 4.2 Create DBFS Upload Automation
**Goal**: Automate sample data uploads to DBFS or Unity Catalog volumes

**Implementation**:
- [ ] Use `databricks_dbfs_file` resource for DBFS uploads
- [ ] Or use volumes with Azure Blob storage upload
- [ ] Create init script for data generation if needed
- [ ] Document data locations in workspace

---

## Phase 5: Workspace Configuration (MEDIUM PRIORITY)

### 5.1 Configure Workspace Settings
**Goal**: Set up workspace for optimal demo experience with serverless

**Implementation**:
- [ ] Create workspace groups: `demo_users`, `demo_admins`
- [ ] Add service principal for automation (optional)
- [ ] Enable serverless compute at workspace level
- [ ] Set workspace-level settings via provider
- [ ] Configure default compute settings to prefer serverless

**Resources**:
- `databricks_group`
- `databricks_workspace_conf`

**Note**: Cluster policies are not needed when using serverless compute, as there are no clusters to manage or restrict.

---

### 5.2 Add Workspace Directory Structure
**Goal**: Organize workspace with logical folder structure

**Implementation**:
- [ ] Use `databricks_directory` resource
- [ ] Create structure:
  ```
  /Shared/
    ├── demo-notebooks/
    ├── examples/
    ├── tutorials/
    └── templates/
  /Repos/
    └── demos/
  ```
- [ ] Set permissions on directories

---

## Phase 6: Project Organization (LOW PRIORITY)

### 6.1 Modularize Terraform Code
**Goal**: Organize code into reusable modules

**Implementation**:
- [ ] Create `modules/` directory
- [ ] Move workspace resources to `modules/workspace-content/`
- [ ] Move infrastructure to `modules/infrastructure/` (optional)
- [ ] Create `modules/unity-catalog/` for UC resources
- [ ] Update root `main.tf` to call modules

**Benefits**: Reusability, cleaner code, easier maintenance

---

### 6.2 Add Terraform Workspaces Support
**Goal**: Support multiple environments (dev/staging/prod)

**Implementation**:
- [ ] Add `terraform.workspace` conditional logic
- [ ] Create environment-specific `.tfvars` files:
  - `dev.tfvars`
  - `staging.tfvars`
  - `prod.tfvars`
- [ ] Document multi-environment workflow in README

---

### 6.3 Add Pre-commit Hooks and Validation
**Goal**: Ensure code quality and formatting

**Implementation**:
- [ ] Add `.pre-commit-config.yaml`
- [ ] Include `terraform fmt`, `terraform validate`
- [ ] Add `tflint` for linting
- [ ] Document in README

---

## Phase 7: Documentation & Demos (LOW PRIORITY)

### 7.1 Create Comprehensive Demo Guide
**Goal**: Provide step-by-step demo instructions

**Implementation**:
- [ ] Create `DEMO_GUIDE.md`
- [ ] Include:
  - What gets deployed
  - How to access each resource
  - Sample queries/commands to run
  - Expected outputs
  - Cleanup instructions
- [ ] Add screenshots or diagrams

---

### 7.2 Add Video/Tutorial Content
**Goal**: Provide multimedia learning materials

**Implementation**:
- [ ] Create YouTube video or Loom walkthrough
- [ ] Link to external tutorial resources
- [ ] Add notebook with embedded documentation
- [ ] Create interactive demo script

---

## Phase 8: Advanced Features (OPTIONAL)

### 8.1 MLflow Integration
**Goal**: Deploy MLflow experiments and models

**Implementation**:
- [ ] Create `databricks_mlflow_experiment`
- [ ] Deploy sample trained model to model registry
- [ ] Create model serving endpoint
- [ ] Add notebook demonstrating MLflow tracking

---

### 8.2 Serverless SQL Warehouses
**Goal**: Provide serverless SQL Analytics capabilities

**Implementation**:
- [ ] Create `databricks_sql_endpoint` with serverless configuration
- [ ] Use SERVERLESS warehouse type (instant startup, auto-scaling)
- [ ] Create sample SQL queries demonstrating analytics
- [ ] Add dashboards using Databricks SQL
- [ ] Configure query history and monitoring

**Example Serverless SQL Warehouse**:
```hcl
resource "databricks_sql_endpoint" "serverless" {
  name             = "Serverless SQL Warehouse"
  cluster_size     = "2X-Small"
  warehouse_type   = "SERVERLESS"
  auto_stop_mins   = 10
  max_num_clusters = 1

  tags {
    custom_tags {
      key   = "Environment"
      value = "Demo"
    }
  }
}

# Sample query
resource "databricks_query" "sample_analytics" {
  warehouse_id = databricks_sql_endpoint.serverless.id
  display_name = "Sample Analytics Query"
  query_text   = <<-EOT
    SELECT
      date_trunc('day', timestamp) as day,
      count(*) as transaction_count,
      sum(amount) as total_amount
    FROM demo_catalog.samples.sales_transactions
    GROUP BY date_trunc('day', timestamp)
    ORDER BY day DESC
  EOT
}
```

**Benefits**:
- Instant availability (no cold start delays)
- Pay-per-query pricing model
- Automatic scaling based on query complexity
- No warehouse management required

---

### 8.3 Serverless Delta Live Tables Pipeline
**Goal**: Demonstrate DLT for ETL workflows using serverless compute

**Implementation**:
- [ ] Create DLT notebook with pipeline definition
- [ ] Deploy `databricks_pipeline` resource with serverless configuration
- [ ] Configure with sample data source
- [ ] Use serverless DLT for automatic resource management
- [ ] Document pipeline execution

**Example Serverless DLT Configuration**:
```hcl
resource "databricks_pipeline" "serverless_etl" {
  name = "Serverless ETL Pipeline"

  configuration = {
    "pipeline.mode" = "SERVERLESS"
  }

  library {
    notebook {
      path = "/Shared/demo-notebooks/dlt_pipeline"
    }
  }

  catalog = "demo_catalog"
  target  = "etl_output"

  continuous = false
}
```

**Benefits**: Automatic resource provisioning, no cluster sizing decisions, optimal performance tuning by Databricks.

---

### 8.4 Databricks Asset Bundles (DABs) Integration
**Goal**: Modern deployment approach using bundles

**Implementation**:
- [ ] Create `databricks.yml` bundle configuration
- [ ] Migrate workspace resources to bundle format
- [ ] Document bundle deployment workflow
- [ ] Compare Terraform vs DABs approach

---

## Implementation Priority

### Quick Wins (Can be done in < 1 hour):
1. Add databricks_repo for Git integration (1.1)
2. Create 2-3 sample notebooks and deploy (2.1)
3. Enable serverless compute for notebooks (2.2)
4. Upload sample CSV files to storage (4.1)

### High Impact (1-2 hours):
1. Create Unity Catalog structure (3.1)
2. Deploy automated serverless jobs (2.3)
3. Create sample tables in UC (3.2)

### Medium Impact (2-4 hours):
1. Modularize Terraform code (6.1)
2. Add workspace directory structure (5.2)
3. Configure permissions (3.3)

### Long-term Enhancements:
1. MLflow integration (8.1)
2. Serverless SQL Warehouses (8.2)
3. Serverless Delta Live Tables (8.3)
4. DABs migration (8.4)

---

## Resources & References

### Terraform Provider Resources:
- `databricks_repo` - Git repository integration
- `databricks_notebook` - Notebook deployment
- `databricks_cluster` - Cluster configuration
- `databricks_job` - Job/workflow orchestration
- `databricks_catalog`, `databricks_schema`, `databricks_table` - Unity Catalog
- `databricks_grants` - Permissions management
- `databricks_dbfs_file` - File uploads
- `databricks_sql_endpoint` - SQL Warehouses

### Example Repositories:
- https://github.com/databricks/tech-talks
- https://github.com/databricks-demos/
- https://github.com/databricks-academy/

### Documentation:
- [Databricks Terraform Provider Docs](https://registry.terraform.io/providers/databricks/databricks/latest/docs)
- [Unity Catalog Best Practices](https://docs.databricks.com/data-governance/unity-catalog/best-practices.html)
- [Workspace Files](https://docs.databricks.com/repos/index.html)

---

## Notes

- Focus is on rapid deployment and demo readiness
- **Serverless-first**: All compute uses serverless (no cluster management overhead)
- All resources should be configured for low cost (serverless auto-scaling, pay-per-use)
- Avoid complex security configurations (per requirements)
- Prioritize ease of use and quick iteration
- Consider using data sources to fetch existing resources when possible
- Use Terraform outputs to document deployed resources and access URLs
- No traditional clusters are created - everything runs on serverless compute for simplicity