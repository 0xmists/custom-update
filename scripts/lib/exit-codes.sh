#!/usr/bin/env bash
# Exit codes for the custom-update skill.
# All commands return one of these codes.
# 0 = Success
# 1 = General error
# 2 = Validation / Doctor failure
# 3 = Patch application conflict
# 4 = Backup verification failure
# 5 = Restore failure
# 6 = Repository not found
# 7 = Backup not found

EXIT_SUCCESS=0
EXIT_GENERAL_ERROR=1
EXIT_VALIDATION_FAILURE=2
EXIT_PATCH_CONFLICT=3
EXIT_VERIFICATION_FAILURE=4
EXIT_RESTORE_FAILURE=5
EXIT_REPO_NOT_FOUND=6
EXIT_BACKUP_NOT_FOUND=7
