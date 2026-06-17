# IMS Bank Deployment Guide

## Overview

This document describes how to deploy the IMS Bank application using the shell script deployment method.

## Architecture

```
Pipeline Flow:
├── DBB Build (task-dbb-build.sh)
│   └── Outputs: BANKZ.DBB.LOAD (programs, DBDs, PSBs)
├── CICS Deployment (task-wazi-deploy.sh)
│   └── Deploys CICS programs via Wazi Deploy
└── IMS Deployment (task-ims-deploy.sh) ← NEW
    └── Calls: scripts/deploy-ims-bank.sh
```

## Deployment Methods

### Method 1: Integrated Pipeline (Recommended)

The IMS deployment is integrated into the standard pipeline via `task-ims-deploy.sh`:

```bash
# Full pipeline (scan, build, deploy CICS + IMS)
.setup/pipeline-common.sh build-and-deploy
```

### Method 2: Standalone Deployment

Deploy IMS independently after DBB build:

```bash
# Deploy IMS only
./scripts/deploy-ims-bank.sh

# Dry run (preview without execution)
./scripts/deploy-ims-bank.sh --dry-run

# Skip DB2 if already provisioned
./scripts/deploy-ims-bank.sh --skip-db2
```

### Method 3: Task Script

Call the task script directly:

```bash
# Via task script
.setup/tasks/task-ims-deploy.sh
```

## Prerequisites

Before running IMS deployment:

1. **DBB Build Completed**
   - `BANKZ.DBB.LOAD` dataset exists
   - Contains IMS programs, DBDs, and PSBs

2. **IMS Control Region Running**
   - IMS2 control region must be active
   - Verify: `D A,IMS2`

3. **DB2 Subsystem Available**
   - DB2 subsystem for transaction history
   - Script will auto-start if needed

4. **ZOAU Installed**
   - z/OS Open Automation Utilities
   - Configured in config.yaml

## Deployment Phases

The deployment script executes these phases:

### Phase 1: Environment Setup
- Load configuration from config.yaml
- Verify DBB outputs exist
- Check IMS control region status
- Verify/start DB2 subsystem

### Phase 2: DB2 Provisioning
- Configure RACF authorization
- Create IMSBANK database
- Create HISTORY table
- Bind DB2 plans
- Load transaction history data

### Phase 3: IMS Dataset Creation & Deployment
- Create IMS runtime datasets (BANKZ.IMS2.*)
- Copy programs from BANKZ.DBB.LOAD → BANKZ.IMS2.PGMLIB
- Copy DBDs from BANKZ.DBB.LOAD → BANKZ.IMS2.DBDLIB
- Copy PSBs from BANKZ.DBB.LOAD → BANKZ.IMS2.PSBLIB

### Phase 4: IMS Control Block Activation
- Generate ACBs from DBDs/PSBs
- Populate IMS catalog
- Import and create IMS resources (SPOC commands)

### Phase 5: Database Loading
- Load ACCOUNT database
- Load CUSTOMER database
- Load CUSTACCS database
- Load HISTORY database
- Load TSTAT database
- Register databases to RECON

### Phase 6: MPP Region Provisioning
- Create and start MPP2 region
- Create and start MPP1 region

### Phase 7: JMP Region Provisioning
- Create JVM properties file (dfsjvmpr.props)
- Create JMP region (IMS2JMP1)
- Configure JVM environment
- Deploy Java application
- Start JMP region

### Phase 8: Verification
- Verify DB2 tables
- Verify IMS databases
- Verify MPP regions
- Verify JMP region
- Display deployment summary

## Configuration

All configuration is loaded from `.setup/config/config.yaml`:

```yaml
ims:
  host: localhost
  port: 9977
  datastore: IMS2
  ims_sys_hlq: IMSV15
  ims_hlq: BANKZ.IMS2
  ims_home: /usr/lpp/ims/ims15
```

## Logging

Deployment logs are written to:
- Console output (real-time)
- Log file: `/tmp/ims-bank-deploy-<pid>/deploy-<timestamp>.log`
- Job outputs: `/tmp/ims-bank-deploy-<pid>/<jobid>.log`

## Troubleshooting

### DBB Output Not Found
```
ERROR: DBB output dataset not found: BANKZ.DBB.LOAD
```
**Solution**: Run DBB build first:
```bash
.setup/tasks/task-dbb-build.sh full
```

### IMS Control Region Not Active
```
ERROR: IMS control region IMS2 is not active
```
**Solution**: Start IMS control region before deployment

### DB2 Not Active
The script will automatically attempt to start DB2. If it fails:
```bash
# Manually start DB2
opercmd "-DBG1 START DB2"
```

### ZOAU Not Found
```
ERROR: ZOAU not found
```
**Solution**: Install ZOAU and configure in config.yaml:
```yaml
zoau:
  zoau_home: /usr/lpp/IBM/zoautil
```

## Integration with Pipeline

To integrate IMS deployment into the pipeline, add to `.setup/pipeline-common.sh`:

```bash
# After CICS deployment
stage_deploy_ims_bank() {
    print_stage "STAGE: Deploy IMS Bank"
    
    if [ ! -f "$BANK_DIR/.setup/tasks/task-ims-deploy.sh" ]; then
        print_error "IMS deployment script not found"
        exit 1
    fi
    
    if bash ${BANK_DIR}/.setup/tasks/task-ims-deploy.sh; then
        print_success "IMS Bank deployment completed successfully"
    else
        print_error "Failed to deploy IMS Bank"
        exit 1
    fi
}
```

## Verification

After deployment, verify IMS Bank is operational:

### 1. Check IMS Regions
```bash
# Check MPP regions
opercmd "D A,IMS2MPP1"
opercmd "D A,IMS2MPP2"

# Check JMP region
opercmd "D A,IMS2JMP1"
```

### 2. Check IMS Databases
```bash
# Query database status
opercmd "/DIS DB ACCOUNT"
opercmd "/DIS DB CUSTOMER"
opercmd "/DIS DB HISTORY"
```

### 3. Check DB2 Tables
```bash
# Verify HISTORY table
db2 "SELECT COUNT(*) FROM IMSBANK.HISTORY"
```

### 4. Test Transactions
Use z/OS Connect or IMS Connect to test transactions:
- IBACSUM: Account summary
- IBGCUDAT: Get customer data
- IBTRAN: Transaction processing

## Rollback

If deployment fails, the script provides rollback capability:

```bash
# Manual rollback steps
1. Stop IMS regions
2. Delete IMS datasets (BANKZ.IMS2.*)
3. Drop DB2 database
4. Review logs for errors
```

## Related Documentation

- [IMS Deployment Plan](../IMS-DEPLOYMENT-PLAN.md) - Detailed technical plan
- [Configuration Guide](CONFIGURATION.md) - config.yaml reference
- [Pipeline Workflow](WORKFLOW-VSCODE.md) - VSCode task integration

## Support

For issues or questions:
1. Check deployment logs
2. Review troubleshooting section
3. Verify prerequisites
4. Consult IMS-DEPLOYMENT-PLAN.md for technical details

---
**Last Updated**: 2026-06-16  
**Version**: 1.0