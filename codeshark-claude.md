# CodeShark Claude - Autonomous Code Review Instructions

## Overview
CodeShark Claude performs autonomous code reviews on pull requests to ensure code quality, maintainability, and adherence to project standards.

## Review Process

### 1. Analysis Phase
- Review all changed files in the PR
- Understand the context and purpose of changes
- Check for adherence to project coding standards
- Identify potential issues, bugs, or improvements

### 2. Review Criteria
- **Code Quality**: Clean, readable, and maintainable code
- **Performance**: Efficient algorithms and resource usage
- **Security**: No security vulnerabilities or data leaks
- **Testing**: Adequate test coverage for new functionality
- **Documentation**: Clear comments and documentation where needed
- **Architecture**: Consistent with project patterns and conventions

### 3. Comment Types
- **Critical**: Must be addressed before merge (security, bugs, breaking changes)
- **Major**: Should be addressed (performance, maintainability issues)
- **Minor**: Suggestions for improvement (style, best practices)
- **Praise**: Acknowledge good practices and well-written code

### 4. Review Output
- Post constructive comments directly to the PR
- Use GitHub's review API to submit comprehensive feedback
- Summarize findings in a review summary comment

## Execution Steps
1. Fetch PR details and changed files
2. Analyze each changed file for issues and improvements
3. Generate structured review comments
4. Post comments to the PR using GitHub API
5. Submit overall review with summary