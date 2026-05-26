function normalizeOutput(value) {
  return (value ?? '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
}

export function validateTutorialStep(step, files, runResult) {
  const validation = step?.validation;
  if (!validation) {
    return {complete: true, message: null};
  }

  if (!runResult) {
    return {complete: false, message: 'Run the program to check this exercise.'};
  }

  if (!runResult.ok) {
    return {complete: false, message: 'Fix the run result before continuing.'};
  }

  if (validation.expectedOutput != null &&
      normalizeOutput(runResult.stdout) !== normalizeOutput(validation.expectedOutput)) {
    return {
      complete: false,
      message: `Expected output ${JSON.stringify(validation.expectedOutput.trimEnd())}.`,
    };
  }

  if (validation.requiredText) {
    const hasRequiredText = files.some((file) => file.code.includes(validation.requiredText));
    if (!hasRequiredText) {
      return {complete: false, message: `Use ${validation.requiredText} in the code before continuing.`};
    }
  }

  return {complete: true, message: validation.successMessage};
}
