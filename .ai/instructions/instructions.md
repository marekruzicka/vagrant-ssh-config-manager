---
applyTo: '**'
---
# Coding standards, domain knowledge, and preferences that AI should follow.

These instructions guide AI-assisted code contributions to ensure precision, maintainability, and alignment with project architecture. Follow each rule exactly unless explicitly told otherwise.

1. **Minimize Scope of Change**  
   - Identify the smallest unit (function, class, or module) that fulfills the requirement.  
   - Do not modify unrelated code.  
   - Avoid refactoring unless required for correctness or explicitly requested.

2. **Preserve System Behavior**  
   - Ensure the change does not affect existing features or alter outputs outside the intended scope.  
   - Maintain original patterns, APIs, and architectural structure unless otherwise instructed.

3. **Graduated Change Strategy**  
   - **Default:** Implement the minimal, focused change.  
   - **If Needed:** Apply small, local refactorings (e.g., rename a variable, extract a function).  
   - **Only if Explicitly Requested:** Perform broad restructuring across files or modules.

4. **Clarify Before Acting on Ambiguity**  
   - If the task scope is unclear or may impact multiple components, stop and request clarification.  
   - Never assume broader intent beyond the described requirement.

5. **Log, Don’t Implement, Unscoped Enhancements**  
   - Identify and note related improvements without changing them.  
   - Example: `// Note: Function Y may benefit from similar validation.`

6. **Ensure Reversibility**  
   - Write changes so they can be easily undone.  
   - Avoid cascading or tightly coupled edits.

7. **Code Quality Standards**  
   - **Clarity:** Use descriptive names. Keep functions short and single-purpose.  
   - **Consistency:** Match existing styles, patterns, and naming.  
   - **Error Handling:** Use try/except (Python) or try/catch (JS/TS). Anticipate failures (e.g., I/O, user input).  
   - **Security:** Sanitize inputs. Avoid hardcoding secrets. Use environment variables for config.  
   - **Testability:** Enable unit testing. Prefer dependency injection over global state.  
   - **Documentation:**  
     - Use DocStrings (`"""Description"""`) for Python.  
     - Use JSDoc (`/** @param {Type} name */`) for JavaScript/TypeScript.  
     - Comment only non-obvious logic.

8. **Testing Requirements**  
   - Add or modify only tests directly related to your change.  
   - Ensure both success and failure paths are covered.  
   - Do not delete existing tests unless explicitly allowed.

9. **Commit Message Format**  
   - Use the [Conventional Commits](
https://www.conventionalcommits.org
) format.  
   - Structure: `type(scope): message`, using imperative mood.  
   - Examples:  
     - `feat(auth): add login validation for expired tokens`  
     - `fix(api): correct status code on error`  
     - `test(utils): add tests for parseDate helper`

10. **Forbidden Actions Unless Explicitly Requested**  
    - Global refactoring across files  
    - Changes to unrelated modules  
    - Modifying formatting or style-only elements without functional reason  
    - Adding new dependencies

11. **Handling Ambiguous References**
    - When encountering ambiguous terms (e.g., "this component", "the helper"), 
      always refer to the exact file path and line numbers when possible
    - If exact location is unclear, ask for clarification before proceeding
    - Never assume the meaning of ambiguous references

Always act within the described scope and prompt constraints. If unsure—ask first.