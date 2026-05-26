import assert from 'node:assert/strict';
import {describe, it} from 'node:test';
import {validateTutorialStep} from './tutorialValidation.mjs';

const exerciseStep = {
  validation: {
    expectedOutput: 'Hello, Playground!\n',
    requiredText: 'Playground',
    successMessage: 'The output matches the expected greeting.',
  },
};

describe('validateTutorialStep', () => {
  it('allows informational steps to advance without a run result', () => {
    assert.deepEqual(validateTutorialStep({validation: null}, [], null), {
      complete: true,
      message: null,
    });
  });

  it('requires an exercise run before unlocking next', () => {
    assert.deepEqual(validateTutorialStep(exerciseStep, [], null), {
      complete: false,
      message: 'Run the program to check this exercise.',
    });
  });

  it('keeps exercises locked when output differs', () => {
    const result = validateTutorialStep(
      exerciseStep,
      [{name: 'Program.nl', code: 'print "Hello, Playground!"'}],
      {ok: true, stdout: 'Hello, N#!\n'},
    );

    assert.equal(result.complete, false);
    assert.equal(result.message, 'Expected output "Hello, Playground!".');
  });

  it('keeps exercises locked until required source text is present', () => {
    const result = validateTutorialStep(
      exerciseStep,
      [{name: 'Program.nl', code: 'print "Hello!"'}],
      {ok: true, stdout: 'Hello, Playground!\n'},
    );

    assert.deepEqual(result, {
      complete: false,
      message: 'Use Playground in the code before continuing.',
    });
  });

  it('unlocks exercises when the run and source match the rule', () => {
    assert.deepEqual(
      validateTutorialStep(
        exerciseStep,
        [{name: 'Program.nl', code: 'print "Hello, Playground!"'}],
        {ok: true, stdout: 'Hello, Playground!\n'},
      ),
      {
        complete: true,
        message: 'The output matches the expected greeting.',
      },
    );
  });
});
