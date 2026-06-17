# IMS Bank Deployment Plan - Shell Script Implementation

## Overview
This document outlines the plan to deploy IMS Bank using shell scripts instead of Ansible, leveraging the existing Ansible JCL templates and structure.

## Current State Analysis

### What Ansible Does (imsbank_provisioning/)
1. **DB2 Provisioning** (provision-db2 role)
   - Configure RACF authorization for DB2
   - Start DB2 subsystem if not active
   - Create DEB user for DB2 access
   - Drop/Create DB2 database and HISTORY table
   - Bind DB2 plans
   - Load transaction history data

2. **IMS Application Configuration** (configure-ims-bank role)
   - Create IMS datasets (PGMLIB, PSBLIB, DBDLIB, ACBLIB, etc.)
   - Copy USS files to MVS datasets
   - Assemble DBDs (Database Descriptors)
   - Assemble PSBs (Program Specification Blocks)
   - Generate ACBs (Application Control Blocks)
   - Populate IMS catalog with managed ACBs
   - Import and create IMS resources
   - Compile COBOL programs (IBACSUM, IBTRAN, etc.)
   - Compile PL/I program (IBLOGIN)
   - Load IMS databases (ACCOUNT, CUSTOMER, HISTORY, TSTAT)
   - Register databases to RECON

3. **MPP Region Provisioning** (provision-mpp role)
   - Create MPP region datasets and procedures
   - Configure MPP1 and MPP2 regions
   - Start MPP regions

4. **JMP Region Provisioning** (provision-jmp role)
   - Create JMP region datasets and procedures
   - Configure JVM properties
   - Create JVM work datasets
   - Start JMP region (IMS2JMP1)

### Key Differences from CICS
- **CICS**: Deployed by Wazi Deploy (automated)
- **IMS**: Currently uses Ansible, needs shell script conversion
- **DB2 for IMS**: Separate from CICS DB2, stores transaction history only
- **IMS Databases**: Hierarchical (ACCOUNT, CUSTOMER, HISTORY, TSTAT) - not DB2

## Deployment Strategy

### Approach: Reuse Ansible JCL Templates
Instead of rewriting all JCL from scratch, we'll:
1. Reuse existing Ansible Jinja2 templates (.j2 files)
2. Convert them to plain JCL by substituting variables
3. Submit JCL via shell script using z/OS utilities

### Prerequisites
- **DBB build completed** - All compilation and assembly done:
  - All outputs in single PDS: **BANKZ.DBB.LOAD**
  - IMS COBOL programs (deployType: IMSLOAD): IBACSUM, IBGCUDAT, IBLOGIN1, IBLOGOUT, IBSCUDAT, IBTRAN
  - IMS PL/I program (deployType: IMSLOAD): IBLOGIN
  - DBDs assembled (deployType: DBDLOAD): ACCOUNT, ACCTYPE, CUSTACCS, CUSTOMER, CUSTTYPE, HISTORY, TSTAT, TSTATTYP, TTYPE
  - PSBs assembled (deployType: PSBLOAD): IB, IBACSUM, IBGCUDAT, IBLOAD, IBLOGIN, IBLOGOUT, IBSCUDAT, IBTRAN
  - Java JMP application built (Maven)
- IMS Control Region (IMS2) running
- DB2 subsystem available
- RACF permissions configured

## Shell Script Structure

### Main Script: `deploy-ims-bank.sh`

```
deploy-ims-bank.sh
├── Phase 1: Environment Setup
│   ├── Load configuration variables
│   ├── Validate prerequisites
│   └── Create temporary USS directory
│
├── Phase 2: DB2 Provisioning
│   ├── Configure RACF for DB2
│   ├── Start DB2 subsystem
│   ├── Create DEB user
│   ├── Drop/Create database
│   ├── Bind DB2 plans
│   └── Load transaction history
│
├── Phase 3: IMS Dataset Creation & Deployment
│   ├── Create BANKZ.IMS2.* runtime datasets
│   ├── Copy DBB outputs to IMS datasets:
│   │   ├── BANKZ.V0R1M0.LOADLIB → BANKZ.IMS2.PGMLIB
│   │   ├── BANKZ.V0R1M0.DBDLOAD → BANKZ.IMS2.DBDLIB
│   │   └── BANKZ.V0R1M0.PSBLOAD → BANKZ.IMS2.PSBLIB
│   ├── Copy USS files to MVS
│   └── Create dynamic allocation datasets
│
├── Phase 4: IMS Control Block Activation
│   ├── Generate ACBs from DBDs/PSBs → ACBLIB
│   ├── Populate IMS catalog with ACBs
│   └── Import/Create IMS resources (SPOC commands)
│
├── Phase 5: Database Loading
│   ├── Load ACCOUNT database
│   ├── Load CUSTOMER database
│   ├── Load CUSTACCS database
│   ├── Load HISTORY database
│   ├── Load TSTAT database
│   └── Register databases to RECON
│
├── Phase 6: MPP Region Provisioning
│   ├── Create MPP2 region
│   ├── Start MPP2
│   ├── Create MPP1 region
│   └── Start MPP1
│
├── Phase 7: JMP Region Provisioning
│   ├── Create JMP region
│   ├── Configure JVM
│   ├── Deploy Java application (from DBB build)
│   └── Start JMP region
│
└── Phase 8: Verification
    ├── Verify DB2 tables
    ├── Verify IMS databases
    ├── Verify MPP regions
    ├── Verify JMP region
    └── Display deployment summary
```

## Configuration Files

### 1. Load Configuration from config.yaml
The shell script should read configuration from `.setup/config/config.yaml` instead of hardcoding values:

```bash
# Load configuration from config.yaml using yq or Python
load_config() {
    local config_file=".setup/config/config.yaml"
    
    # Parse YAML and export variables
    # Using yq (YAML processor)
    export SANDBOX_PATH=$(yq eval '.sandbox.path' "$config_file")
    export APP_BASE_NAME=$(yq eval '.app.base_name' "$config_file")
    export APP_ZOS_VERSION=$(yq eval '.app.zos_version' "$config_file")
    export IMS_HLQ=$(yq eval '.ims.ims_hlq' "$config_file")
    export IMS_DATASTORE=$(yq eval '.ims.datastore' "$config_file")
    export IMS_HOST=$(yq eval '.ims.host' "$config_file")
    export IMS_PORT=$(yq eval '.ims.port' "$config_file")
    
    # Derived paths
    export SOURCE_DIR="${SANDBOX_PATH}/${REPO_NAME}/src/base/ims"
    export LOAD_DATA_DIR="${SOURCE_DIR}/LoadData"
    export DBB_LOAD="${APP_BASE_NAME}.DBB.LOAD"
    
    # IMS Configuration (from Ansible vars or environment)
    export IMS_REGION=${IMS_DATASTORE}  # IMS2
    export IMS_PLEX=${IMS_PLEX:-IMSPLEX2}  # Default to IMSPLEX2
    
    # DB2 Configuration (from environment or defaults)
    export DB2_SSID=${DB2_SSID:-DBG1}
    export DB2_DATABASE=${DB2_DATABASE:-IMSBANK}
    export DB2_TABLE=${DB2_TABLE:-HISTORY}
    
    # Dataset Names
    export PGMLIB="${IMS_HLQ}.PGMLIB"
    export PSBLIB="${IMS_HLQ}.PSBLIB"
    export DBDLIB="${IMS_HLQ}.DBDLIB"
    export ACBLIB="${IMS_HLQ}.ACBLIB"
    
    # USS Paths
    export USS_WORK_DIR="/tmp/ims-bank-deploy"
    
    # JCL Job Card
    export JOB_CARD="//IMSBANKJ JOB (ACCT),'IMS BANK',CLASS=A,MSGCLASS=H,NOTIFY=&SYSUID"
}
```

**Alternative: Using Python to parse YAML**
```bash
load_config_python() {
    python3 << 'EOF'
import yaml
import os

with open('.setup/config/config.yaml', 'r') as f:
    config = yaml.safe_load(f)

# Export variables
os.environ['SANDBOX_PATH'] = config['sandbox']['path']
os.environ['APP_BASE_NAME'] = config['app']['base_name']
os.environ['IMS_HLQ'] = config['ims']['ims_hlq']
os.environ['IMS_DATASTORE'] = config['ims']['datastore']

# Print export statements for shell to eval
print(f"export SANDBOX_PATH='{config['sandbox']['path']}'")
print(f"export APP_BASE_NAME='{config['app']['base_name']}'")
print(f"export IMS_HLQ='{config['ims']['ims_hlq']}'")
print(f"export IMS_DATASTORE='{config['ims']['datastore']}'")
EOF
}

# Load and eval
eval "$(load_config_python)"
```

### 2. `templates/` Directory
Reuse Ansible templates with variable substitution:
- `CREATEDATA.jcl` - Create IMS datasets
- `DBDGEN.jcl` - Assemble DBDs
- `PSBGEN.jcl` - Assemble PSBs
- `ACBGEN.jcl` - Generate ACBs
- `IBCMPLNK.jcl` - Compile COBOL programs
- `PLICMLK.jcl` - Compile PL/I program
- `LOAD*.jcl` - Load databases
- `RECON.jcl` - Register to RECON
- `CRE_DFSMPR.jcl` - Create MPP region
- `CRE_DFSJMP.jcl` - Create JMP region

## ZOAU Integration

The deployment script uses **ZOAU (z/OS Open Automation Utilities)** for all z/OS operations, consistent with the rest of the codebase.

### ZOAU Setup
```bash
# ZOAU environment (loaded from config.yaml)
export ZOAU_HOME=$(get_section_value 'zoau' 'zoau_home')
export PATH="$ZOAU_HOME/bin:$PATH"
export LIBPATH="$ZOAU_HOME/lib:${LIBPATH:-}"

# Verify ZOAU version
zoaversion
```

### Key ZOAU Commands Used
**Note**: Verify these commands against your ZOAU version (1.4.1 or later). Command syntax may vary between versions.

- **jsub**: Submit JCL jobs to z/OS
- **jls**: List and query job status
- **jcat**: Display job output (spool files)
- **dls**: List datasets and members
- **opercmd**: Issue operator commands
- **mvscmd**: Execute MVS commands

### ZOAU Command Reference
For the specific ZOAU version installed, refer to:
- ZOAU documentation: `$ZOAU_HOME/docs/`
- IBM Knowledge Center: https://www.ibm.com/docs/en/zoau
- Command help: `<command> --help` (e.g., `jsub --help`)

## Key Functions

### 1. `submit_jcl()` - Using ZOAU
Submit JCL and wait for completion using ZOAU jsub/jls/jcat:
```bash
submit_jcl() {
    local jcl_file=$1
    local max_rc=${2:-0}
    
    log "Submitting JCL: $jcl_file"
    
    # Submit JCL using ZOAU jsub command
    local output=$(jsub "$jcl_file" 2>&1)
    local job_id=$(echo "$output" | grep -oE 'JOB[0-9]+' | head -1)
    
    if [ -z "$job_id" ]; then
        log_error "Failed to submit JCL: $jcl_file"
        echo "$output"
        return 1
    fi
    
    log "Job submitted: $job_id"
    
    # Wait for job completion using ZOAU jls
    wait_for_job "$job_id" "$max_rc"
}

wait_for_job() {
    local job_id=$1
    local max_rc=$2
    
    log "Waiting for job $job_id to complete..."
    
    # Poll job status using ZOAU jls
    local status=""
    local rc=""
    local elapsed=0
    
    while true; do
        # Query job status with jls
        local job_info=$(jls -j "$job_id" 2>/dev/null || echo "")
        
        if [ -z "$job_info" ]; then
            log_error "Job $job_id not found"
            return 1
        fi
        
        # Parse status and return code from jls output
        status=$(echo "$job_info" | awk '{print $2}')
        rc=$(echo "$job_info" | awk '{print $3}')
        
        case "$status" in
            "OUTPUT"|"COMPLETE")
                log "Job $job_id completed with RC=$rc"
                
                # Get job output using ZOAU jcat
                jcat -j "$job_id" > "${USS_WORK_DIR}/${job_id}.log"
                
                if [ "$rc" -gt "$max_rc" ]; then
                    log_error "Job $job_id failed with RC=$rc (max allowed: $max_rc)"
                    cat "${USS_WORK_DIR}/${job_id}.log"
                    return 1
                fi
                
                return 0
                ;;
            "ACTIVE"|"INPUT"|"HELD")
                printf "\r[INFO] Job $job_id status: %-10s (elapsed: %ds)" "$status" "$elapsed"
                sleep 5
                elapsed=$((elapsed + 5))
                ;;
            "ABEND")
                log_error "Job $job_id abended"
                jcat -j "$job_id"
                return 1
                ;;
            *)
                log_warning "Unknown job status: $status"
                sleep 5
                elapsed=$((elapsed + 5))
                ;;
        esac
    done
}
```

### 2. `copy_ims_programs()`
Copy IMS program members from DBB output to PGMLIB:
```bash
copy_ims_programs() {
    local source_ds=$1
    local target_ds=$2
    
    # IMS programs (deployType: IMSLOAD)
    local programs="IBACSUM,IBGCUDAT,IBLOGIN1,IBLOGOUT,IBSCUDAT,IBTRAN,IBLOGIN"
    
    # Use IEBCOPY to copy specific members
    submit_jcl <<EOF
//COPYIMS  EXEC PGM=IEBCOPY
//SYSPRINT DD SYSOUT=*
//SYSUT1   DD DISP=SHR,DSN=${source_ds}
//SYSUT2   DD DISP=SHR,DSN=${target_ds}
//SYSIN    DD *
  COPY OUTDD=SYSUT2,INDD=SYSUT1
  SELECT MEMBER=((${programs}))
/*
EOF
}
```

### 3. `copy_ims_dbds()`
Copy DBD members from DBB output to DBDLIB:
```bash
copy_ims_dbds() {
    local source_ds=$1
    local target_ds=$2
    
    # DBDs (deployType: DBDLOAD)
    local dbds="ACCOUNT,ACCTYPE,CUSTACCS,CUSTOMER,CUSTTYPE,HISTORY,TSTAT,TSTATTYP,TTYPE"
    
    submit_jcl <<EOF
//COPYDBD  EXEC PGM=IEBCOPY
//SYSPRINT DD SYSOUT=*
//SYSUT1   DD DISP=SHR,DSN=${source_ds}
//SYSUT2   DD DISP=SHR,DSN=${target_ds}
//SYSIN    DD *
  COPY OUTDD=SYSUT2,INDD=SYSUT1
  SELECT MEMBER=((${dbds}))
/*
EOF
}
```

### 4. `copy_ims_psbs()`
Copy PSB members from DBB output to PSBLIB:
```bash
copy_ims_psbs() {
    local source_ds=$1
    local target_ds=$2
    
    # PSBs (deployType: PSBLOAD)
    local psbs="IB,IBACSUM,IBGCUDAT,IBLOAD,IBLOGIN,IBLOGOUT,IBSCUDAT,IBTRAN"
    
    submit_jcl <<EOF
//COPYPSB  EXEC PGM=IEBCOPY
//SYSPRINT DD SYSOUT=*
//SYSUT1   DD DISP=SHR,DSN=${source_ds}
//SYSUT2   DD DISP=SHR,DSN=${target_ds}
//SYSIN    DD *
  COPY OUTDD=SYSUT2,INDD=SYSUT1
  SELECT MEMBER=((${psbs}))
/*
EOF
}
```

### 5. `substitute_variables()`
Replace Jinja2 variables with actual values:
```bash
substitute_variables() {
    local template=$1
    local output=$2
    
    sed -e "s|{{ IMS_REGION }}|${IMS_REGION}|g" \
        -e "s|{{ DB2SSID }}|${DB2_SSID}|g" \
        -e "s|{{ IMS_HLQ }}|${IMS_HLQ}|g" \
        "$template" > "$output"
}
```

### 6. `verify_dbb_outputs()`
Verify DBB build outputs exist before deployment:
```bash
verify_dbb_outputs() {
    local dbb_load="BANKZ.DBB.LOAD"
    
    if ! verify_dataset "$dbb_load"; then
        log_error "DBB output dataset not found: $dbb_load"
        log_error "Please run DBB build first"
        return 1
    fi
    
    # Verify required IMS members exist
    local required_members=(
        "IBACSUM" "IBGCUDAT" "IBLOGIN1" "IBLOGOUT" "IBSCUDAT" "IBTRAN" "IBLOGIN"  # Programs
        "ACCOUNT" "CUSTOMER" "HISTORY" "TSTAT"  # DBDs
        "IBACSUM" "IBGCUDAT" "IBLOGIN" "IBTRAN"  # PSBs
    )
    
    for member in "${required_members[@]}"; do
        if ! verify_member "$dbb_load" "$member"; then
            log_error "Required member not found in $dbb_load: $member"
            return 1
        fi
    done
    
    log "All DBB output members verified in $dbb_load"
    return 0
}
```

### 7. `verify_dataset()` - Using ZOAU
Check if dataset exists using ZOAU dls:
```bash
verify_dataset() {
    local dsn=$1
    
    # Use ZOAU dls to check if dataset exists
    dls "$dsn" >/dev/null 2>&1
    return $?
}
```

### 8. `verify_member()` - Using ZOAU
Check if member exists in PDS using ZOAU dls:
```bash
verify_member() {
    local dsn=$1
    local member=$2
    
    # Use ZOAU dls to check if member exists
    dls "${dsn}(${member})" >/dev/null 2>&1
    return $?
}
```

### 9. `check_db2_active()` - Using ZOAU
Verify DB2 subsystem is running using ZOAU opercmd:
```bash
check_db2_active() {
    local ssid=$1
    
    # Use ZOAU opercmd to check if DB2 is active
    local output=$(opercmd "D A,${ssid}MSTR" 2>&1)
    
    if echo "$output" | grep -q "${ssid}MSTR"; then
        log "DB2 subsystem $ssid is active"
        return 0
    else
        log_warning "DB2 subsystem $ssid is not active"
        return 1
    fi
}

start_db2() {
    local ssid=$1
    
    log "Starting DB2 subsystem $ssid..."
    opercmd "-${ssid} START DB2"
    
    # Wait for DB2 to start
    local retries=12
    local delay=5
    
    for ((i=1; i<=retries; i++)); do
        if check_db2_active "$ssid"; then
            log "DB2 subsystem $ssid started successfully"
            return 0
        fi
        log "Waiting for DB2 to start... (attempt $i/$retries)"
        sleep $delay
    done
    
    log_error "DB2 subsystem $ssid failed to start"
    return 1
}
```

### 10. `check_ims_control_region()` - Using ZOAU
Verify IMS control region is running:
```bash
check_ims_control_region() {
    local ims_region=$1
    
    # Use ZOAU opercmd to check if IMS control region is active
    local output=$(opercmd "D A,${ims_region}" 2>&1)
    
    if echo "$output" | grep -q "${ims_region}"; then
        log "IMS control region $ims_region is active"
        return 0
    else
        log_error "IMS control region $ims_region is not active"
        log_error "Please start IMS control region before deployment"
        return 1
    fi
}
```

### 11. `create_jvm_properties_file()`
Create dfsjvmpr.props file for JMP region JVM configuration:
```bash
create_jvm_properties_file() {
    local props_file="${JAVA_CONF_PATH}/dfsjvmpr.props"
    local jar_file="${ANSIBLE_DIR}/nazare-ims-jmp-1.0.0-SNAPSHOT.jar"
    
    log "Creating JVM properties file: $props_file"
    
    # Create the properties file with Java classpath and library path
    cat > "$props_file" << EOF
-Djava.class.path=${IMS_JAVA_HOME}/imsudb.jar:${jar_file}:${DB2_JAVA_HOME}/jdbc/classes/db2jcc.jar:${DB2_JAVA_HOME}/jdbc/classes/db2jcc_license_cisuz.jar
-Djava.library.path=${IMS_JAVA_HOME}/lib:${DB2_JAVA_HOME}/jdbc/lib:${DB2_JAVA_HOME}/lib
EOF
    
    # Convert to EBCDIC encoding for z/OS
    iconv -f ISO8859-1 -t IBM-1047 "$props_file" > "${props_file}.tmp"
    chtag -tc IBM-1047 "${props_file}.tmp"
    mv "${props_file}.tmp" "$props_file"
    
    log "JVM properties file created and converted to EBCDIC"
    
    # Verify file exists
    if [ -f "$props_file" ]; then
        log "JVM properties file verified: $props_file"
        return 0
    else
        log_error "Failed to create JVM properties file"
        return 1
    fi
}
```

## Execution Flow

### Phase-by-Phase Execution

#### Phase 1: Environment Setup
```bash
# Load configuration from config.yaml
load_config

# Create work directory
mkdir -p "$USS_WORK_DIR"
cd "$USS_WORK_DIR"

# Validate prerequisites
verify_dbb_outputs  # Ensure DBB build completed
check_ims_control_region
check_db2_subsystem
check_racf_permissions
```

#### Phase 2: DB2 Provisioning
```bash
# Configure RACF
substitute_variables templates/DB2-RACF.j2 DB2-RACF.jcl
submit_jcl DB2-RACF.jcl 4

# Start DB2 if needed
if ! check_db2_active "$DB2_SSID"; then
    opercmd "-${DB2_SSID} START DB2"
    wait_for_db2_active
fi

# Create database
substitute_variables templates/Db2-create.j2 Db2-create.jcl
submit_jcl Db2-create.jcl 8

# Bind plans
substitute_variables templates/Db2-bind.j2 Db2-bind.jcl
submit_jcl Db2-bind.jcl 0

# Load data
substitute_variables templates/LOADDB2.j2 LOADDB2.jcl
submit_jcl LOADDB2.jcl 8
```

#### Phase 3: IMS Dataset Creation & Deployment
```bash
# Create IMS runtime datasets
substitute_variables templates/CREATEDATA.j2 CREATEDATA.jcl
submit_jcl CREATEDATA.jcl 0

# Copy DBB build outputs to IMS runtime datasets
# All outputs are in BANKZ.DBB.LOAD, need to copy specific members
copy_ims_programs "BANKZ.DBB.LOAD" "BANKZ.IMS2.PGMLIB"
copy_ims_dbds "BANKZ.DBB.LOAD" "BANKZ.IMS2.DBDLIB"
copy_ims_psbs "BANKZ.DBB.LOAD" "BANKZ.IMS2.PSBLIB"

# Copy USS files to MVS
substitute_variables templates/CPTOMVS.j2 CPTOMVS.sh
chmod +x CPTOMVS.sh
./CPTOMVS.sh

# Dynamic allocation
substitute_variables templates/DYNALLOC.j2 DYNALLOC.jcl
submit_jcl DYNALLOC.jcl 0
```

#### Phase 4: IMS Control Block Activation
```bash
# Generate ACBs from DBDs/PSBs (already assembled by DBB)
substitute_variables templates/ACBGEN.j2 ACBGEN.jcl
submit_jcl ACBGEN.jcl 8

# Populate IMS catalog with ACBs
substitute_variables templates/CATPOP.j2 CATPOP.jcl
submit_jcl CATPOP.jcl 8

# Import and create IMS resources
substitute_variables templates/UPDATE_MACB.j2 UPDATE_MACB.jcl
submit_jcl UPDATE_MACB.jcl 8

substitute_variables templates/SPOCJOB.j2 SPOCJOB.jcl
submit_jcl SPOCJOB.jcl 8
```

#### Phase 5: Database Loading
```bash
# Load each database
for db in LOADACCT LOADCUSA LOADCUST LOADHIST LOADTSTA; do
    substitute_variables "templates/${db}.j2" "${db}.jcl"
    submit_jcl "${db}.jcl" 0
done

# Register to RECON
substitute_variables templates/DELOLDRECON.j2 DELOLDRECON.jcl
submit_jcl DELOLDRECON.jcl 12

substitute_variables templates/RECON.j2 RECON.jcl
submit_jcl RECON.jcl 0
```

#### Phase 6: MPP Region Provisioning
```bash
# MPP2 Region
source config/ims-mpp-2.env
substitute_variables templates/CRE_DFSMPR.j2 CRE_DFSMPR2.jcl
submit_jcl CRE_DFSMPR2.jcl 0

substitute_variables templates/STARTMPP.j2 STARTMPP2.jcl
submit_jcl STARTMPP2.jcl 0

# MPP1 Region
source config/ims-mpp-1.env
substitute_variables templates/CRE_DFSMPR.j2 CRE_DFSMPR1.jcl
submit_jcl CRE_DFSMPR1.jcl 0

substitute_variables templates/STARTMPP.j2 STARTMPP1.jcl
submit_jcl STARTMPP1.jcl 0
```

#### Phase 7: JMP Region Provisioning
```bash
# JMP Region
source config/ims-jmp.env

# Create JVM properties file (dfsjvmpr.props)
create_jvm_properties_file

# Create JCL work datasets
substitute_variables templates/CREWORKDS.j2 CREWORKDS.jcl
submit_jcl CREWORKDS.jcl 4

# Copy DFSJMP proc to PROCLIB
substitute_variables templates/CRE_DFSJMP.j2 CRE_DFSJMP.jcl
submit_jcl CRE_DFSJMP.jcl 0

# Create JMP region
substitute_variables templates/IMDOJMP.j2 IMDOJMP.jcl
submit_jcl IMDOJMP.jcl 4

# Configure JVM environment settings
substitute_variables templates/CREDFSJVMEV.j2 CREDFSJVMEV.jcl
submit_jcl CREDFSJVMEV.jcl 4

# Set Java library classpath
substitute_variables templates/CREDFSJVMMS.j2 CREDFSJVMMS.jcl
submit_jcl CREDFSJVMMS.jcl 4

# Map PSB to Java application
substitute_variables templates/CREDFSJVMAP.j2 CREDFSJVMAP.jcl
submit_jcl CREDFSJVMAP.jcl 4

# Start JMP region
substitute_variables templates/STARTJMP.j2 STARTJMP.jcl
submit_jcl STARTJMP.jcl 0
```

#### Phase 8: Verification
```bash
# Verify DB2
verify_db2_table "$DB2_DATABASE.$DB2_TABLE"

# Verify IMS databases
for db in ACCOUNT CUSTOMER HISTORY TSTAT; do
    verify_ims_database "$db"
done

# Verify regions
verify_mpp_region "IMS2MPP1"
verify_mpp_region "IMS2MPP2"
verify_jmp_region "IMS2JMP1"

# Display summary
display_deployment_summary
```

## Error Handling

### Rollback Strategy
```bash
rollback_deployment() {
    echo "Rolling back deployment..."
    
    # Stop regions
    stop_jmp_region
    stop_mpp_regions
    
    # Delete datasets
    delete_ims_datasets
    
    # Drop DB2 database
    drop_db2_database
    
    echo "Rollback complete"
}

trap rollback_deployment ERR
```

### Logging
```bash
LOG_FILE="$USS_WORK_DIR/deploy-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}
```

## Testing Strategy

### Unit Testing
- Test each function independently
- Mock JCL submission for dry-run mode
- Validate variable substitution

### Integration Testing
- Test on development IMS system first
- Verify each phase completes successfully
- Check dataset contents and region status

### Validation Checks
- DB2 table row count
- IMS database segment counts
- MPP region active status
- JMP region JVM status
- Transaction processing test

## Advantages Over Ansible

1. **Simplicity**: Single shell script, no Python/Ansible dependencies
2. **Transparency**: Direct JCL submission, easier to debug
3. **Portability**: Runs on any z/OS USS environment
4. **Integration**: Can be called from DBB pipeline or CI/CD
5. **Customization**: Easy to modify for different environments
6. **Leverages DBB**: Reuses compiled programs and assembled control blocks from DBB build
7. **No Duplication**: Doesn't recompile what DBB already built

## Key Design Decisions

### Why Not Recompile in Deployment?
- **DBB already compiled** all COBOL and PL/I programs
- **DBB already assembled** all DBDs and PSBs
- **Deployment should only deploy**, not rebuild
- Faster deployment (no compilation time)
- Single source of truth (DBB outputs)

### What Deployment Does
1. **Copy** DBB outputs to IMS runtime datasets
2. **Generate** ACBs from assembled DBDs/PSBs
3. **Activate** IMS resources (catalog, SPOC commands)
4. **Load** databases with test data
5. **Start** IMS regions (MPP, JMP)
6. **Verify** deployment success

## Migration Path

### Phase 1: Create Shell Script Framework
- Implement core functions (submit_jcl, substitute_variables)
- Create configuration files
- Set up logging and error handling

### Phase 2: Convert Ansible Templates
- Copy .j2 templates to shell script templates/
- Update variable syntax from Jinja2 to shell
- Test variable substitution

### Phase 3: Implement Deployment Phases
- Implement each phase sequentially
- Test each phase independently
- Add verification checks

### Phase 4: Integration and Testing
- Test complete deployment flow
- Add rollback capability
- Document usage and troubleshooting

### Phase 5: Production Readiness
- Add dry-run mode
- Implement idempotency checks
- Create deployment runbook

## Success Criteria

- [ ] Shell script successfully deploys IMS Bank
- [ ] DB2 database created and loaded
- [ ] IMS databases loaded with test data
- [ ] MPP regions running and processing transactions
- [ ] JMP region running with Java application
- [ ] All verification checks pass
- [ ] Deployment time < 30 minutes
- [ ] Rollback capability tested
- [ ] Documentation complete

## Next Steps

1. Create `deploy-ims-bank.sh` main script
2. Create configuration files in `config/` directory
3. Convert Ansible templates to shell-compatible JCL
4. Implement core utility functions
5. Test on development system
6. Document usage and troubleshooting
7. Integrate with CI/CD pipeline

---
**Document Version**: 1.0  
**Last Updated**: 2026-06-16  
**Author**: Bob (AI Assistant)