(() => {
  const logEl = document.getElementById('log');
  const metaEl = document.getElementById('meta');
  const questionEl = document.getElementById('question');
  const choicesEl = document.getElementById('choices');
  const statusEl = document.getElementById('status');
  const saveBtn = document.getElementById('save');
  const finishBtn = document.getElementById('finish');

  const state = {
    contract: null,
    game: null,
    answered: false,
    score: 0,
    step: 0,
  };

  function log(message) {
    const line = `[${new Date().toISOString()}] ${message}`;
    if (!logEl.textContent) {
      logEl.textContent = line;
      return;
    }
    logEl.textContent += `\n${line}`;
  }

  function randomId(prefix) {
    return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
  }

  function packageIdFromPath(pathValue) {
    if (!pathValue) {
      return 'unknown_pkg';
    }
    const normalized = String(pathValue).replaceAll('\\', '/').split('/').filter(Boolean);
    if (normalized.length === 0) {
      return 'unknown_pkg';
    }
    return normalized[normalized.length - 1];
  }

  function parseGamePayload(sourceEduvi) {
    if (!sourceEduvi || typeof sourceEduvi !== 'object') {
      return null;
    }

    const games = sourceEduvi.games;
    if (!Array.isArray(games) || games.length === 0) {
      return null;
    }

    const firstGame = games[0];
    if (!firstGame || typeof firstGame !== 'object') {
      return null;
    }

    const resultJson = firstGame.resultJson;
    if (!resultJson || typeof resultJson !== 'object') {
      return null;
    }

    const payload = resultJson.payload;
    if (!payload || typeof payload !== 'object') {
      return null;
    }

    const choices = Array.isArray(payload.choices) ? payload.choices : [];
    const prompt = typeof payload.prompt === 'string' ? payload.prompt : 'Khong co cau hoi';
    const correctChoiceId =
      typeof payload.correctChoiceId === 'string' ? payload.correctChoiceId : null;

    return {
      prompt,
      choices,
      correctChoiceId,
      templateCode:
        typeof firstGame.templateCode === 'string' ? firstGame.templateCode : 'UNKNOWN',
    };
  }

  function updateStatus(text) {
    statusEl.textContent = text;
  }

  function renderGame() {
    if (!state.game) {
      questionEl.textContent = 'Khong tim thay du lieu game trong file .eduvi';
      choicesEl.innerHTML = '';
      updateStatus('Runtime fallback mode.');
      return;
    }

    questionEl.textContent = state.game.prompt;
    choicesEl.innerHTML = '';

    for (const choice of state.game.choices) {
      const button = document.createElement('button');
      button.className = 'choice';
      button.type = 'button';
      const id = typeof choice.id === 'string' ? choice.id : '?';
      const text = typeof choice.text === 'string' ? choice.text : 'Lua chon';
      button.textContent = `${id}. ${text}`;

      button.addEventListener('click', () => {
        if (state.answered) {
          return;
        }
        state.step += 1;
        const isCorrect = id === state.game.correctChoiceId;
        if (isCorrect) {
          state.score += 100;
          button.classList.add('correct');
          updateStatus('Ban da chon dung dap an.');
        } else {
          state.score = Math.max(0, state.score - 20);
          button.classList.add('wrong');
          updateStatus('Ban chon sai dap an.');
        }

        for (const other of choicesEl.querySelectorAll('.choice')) {
          const currentText = other.textContent || '';
          if (currentText.startsWith(`${state.game.correctChoiceId}.`)) {
            other.classList.add('correct');
          }
          other.disabled = true;
        }
        state.answered = true;
      });

      choicesEl.appendChild(button);
    }
  }

  async function saveSnapshot() {
    if (!state.contract) {
      return;
    }

    state.step += 1;
    state.score += 25;

    const payload = {
      snapshotId: randomId('snap'),
      sessionId: state.contract.sessionId,
      packageId: packageIdFromPath(state.contract.packagePath),
      levelId: `level_${Math.max(1, Math.floor(state.step / 3))}`,
      checkpoint: `cp_${state.step}`,
      score: state.score,
      timerMsRemaining: Math.max(0, 180000 - state.step * 1000),
      state: {
        combo: state.step % 6,
        lives: 3,
      },
      createdAt: new Date().toISOString(),
      checksumSha256: 'runtime_generated_checksum',
    };

    await window.eduviGameApi.saveProgressSnapshot(payload);
    log(`Snapshot saved: ${payload.snapshotId}`);
  }

  async function finishSession() {
    if (!state.contract) {
      return;
    }

    const payload = {
      resultId: randomId('result'),
      sessionId: state.contract.sessionId,
      packageId: packageIdFromPath(state.contract.packagePath),
      status: 'completed',
      score: state.score,
      durationMs: Math.max(60000, state.step * 5000),
      accuracy: 0.92,
      completedAt: new Date().toISOString(),
      detail: {
        steps: state.step,
      },
    };

    await window.eduviGameApi.saveGameResult(payload);
    log(`Result saved: ${payload.resultId}`);
  }

  async function bootstrap() {
    try {
      state.contract = await window.eduviGameApi.readLaunchContract();
      const sourceEduvi = await window.eduviGameApi.readSourceEduvi();
      state.game = parseGamePayload(sourceEduvi);
      metaEl.textContent = `Session ${state.contract.sessionId} | Mode ${state.contract.mode} | Package ${state.contract.packagePath}`;
      log('Launch contract loaded. Offline runtime ready.');
      renderGame();

      saveBtn.addEventListener('click', () => {
        void saveSnapshot();
      });
      finishBtn.addEventListener('click', () => {
        void finishSession();
      });

      setInterval(() => {
        void saveSnapshot();
      }, 15000);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      metaEl.textContent = `Runtime initialization failed: ${message}`;
      log(`Error: ${message}`);
    }
  }

  void bootstrap();
})();
