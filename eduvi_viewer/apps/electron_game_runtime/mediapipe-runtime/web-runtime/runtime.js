(() => {
  // â”€â”€ DOM refs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  const logEl = document.getElementById('log');
  const metaEl = document.getElementById('meta');
  const gameContainerEl = document.getElementById('game-container');
  const statusEl = document.getElementById('status');

  // â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  const state = {
    contract: null,
    gameData: null,
    isFinished: false,
    // HOVER_SELECT
    hsAnswered: false,
    hsScore: 0,
    // DRAG_DROP
    ddSelectedItemId: null,
    ddMatched: {},
    ddScore: 0,
    ddTotalItems: 0,
    // SNAKE_DUEL
    sdQuestionIndex: 0,
    sdP1Score: 0,
    sdP2Score: 0,
    sdP1Answered: false,
    sdP2Answered: false,
    sdKeyHandler: null,
  };

  // â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  function log(message) {
    const line = `[${new Date().toISOString()}] ${message}`;
    logEl.textContent = logEl.textContent ? `${logEl.textContent}\n${line}` : line;
  }

  function setStatus(text) {
    statusEl.textContent = text;
  }

  function randomId(prefix) {
    return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
  }

  function packageIdFromPath(pathValue) {
    if (!pathValue) return 'unknown_pkg';
    const parts = String(pathValue).replaceAll('\\', '/').split('/').filter(Boolean);
    return parts.length > 0 ? parts[parts.length - 1] : 'unknown_pkg';
  }

  // â”€â”€ Payload extraction â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  /**
   * Extracts { templateId, settings, scene, payload } from a source .eduvi object.
   * Reads from games[0].resultJson â€” the canonical location in the game export format.
   */
  function extractGameData(sourceEduvi) {
    if (!sourceEduvi || typeof sourceEduvi !== 'object') return null;

    const games = sourceEduvi.games;
    if (!Array.isArray(games) || games.length === 0) return null;

    const firstGame = games[0];
    if (!firstGame || typeof firstGame !== 'object') return null;

    const resultJson = firstGame.resultJson;
    if (!resultJson || typeof resultJson !== 'object') return null;

    // templateId lives in resultJson; templateCode is the legacy API-level field
    const templateId =
      typeof resultJson.templateId === 'string' && resultJson.templateId.trim()
        ? resultJson.templateId.trim()
        : typeof firstGame.templateCode === 'string' && firstGame.templateCode.trim()
          ? firstGame.templateCode.trim()
          : 'UNKNOWN';

    return {
      templateId,
      settings:
        resultJson.settings && typeof resultJson.settings === 'object'
          ? resultJson.settings
          : {},
      scene:
        resultJson.scene && typeof resultJson.scene === 'object' ? resultJson.scene : {},
      payload:
        resultJson.payload && typeof resultJson.payload === 'object'
          ? resultJson.payload
          : null,
    };
  }

  // â”€â”€ Result saving â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  async function saveGameResult(score, detail) {
    if (!state.contract || state.isFinished) return;
    state.isFinished = true;

    const payload = {
      resultId: randomId('result'),
      sessionId: state.contract.sessionId,
      packageId: packageIdFromPath(state.contract.packagePath),
      status: 'completed',
      score,
      durationMs: 60000,
      accuracy: score > 0 ? 0.9 : 0,
      completedAt: new Date().toISOString(),
      detail: detail ?? {},
    };

    try {
      await window.eduviGameApi.saveGameResult(payload);
      log(`Result saved: ${payload.resultId} score=${score}`);
      setStatus('Da luu ket qua. Phien choi ket thuc.');
    } catch (err) {
      log(`Save result error: ${err}`);
    }
  }

  // â”€â”€ HOVER_SELECT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  function renderHoverSelect(payload) {
    const prompt = typeof payload.prompt === 'string' ? payload.prompt : '';
    const choices = Array.isArray(payload.choices) ? payload.choices : [];
    const correctId =
      typeof payload.correctChoiceId === 'string' ? payload.correctChoiceId : null;

    const promptEl = document.createElement('div');
    promptEl.className = 'hs-prompt';
    promptEl.textContent = prompt;
    gameContainerEl.appendChild(promptEl);

    const gridEl = document.createElement('div');
    gridEl.className = 'hs-choices';
    gameContainerEl.appendChild(gridEl);

    const finishBtn = document.createElement('button');
    finishBtn.className = 'btn-finish hidden';
    finishBtn.textContent = 'Ket thuc phien choi';
    finishBtn.addEventListener('click', () => {
      void saveGameResult(state.hsScore, { mode: 'hover_select' });
    });
    gameContainerEl.appendChild(finishBtn);

    for (const choice of choices) {
      const id = typeof choice.id === 'string' ? choice.id : '?';
      const text =
        typeof choice.text === 'string'
          ? choice.text
          : String(choice.label ?? choice.id ?? '');
      const btn = document.createElement('button');
      btn.className = 'choice-btn';
      btn.textContent = text;

      btn.addEventListener('click', () => {
        if (state.hsAnswered) return;
        state.hsAnswered = true;

        const isCorrect = id === correctId;
        if (isCorrect) {
          state.hsScore = 100;
          btn.classList.add('correct');
          setStatus('Dung! Ban da chon dap an chinh xac.');
        } else {
          btn.classList.add('wrong');
          setStatus('Sai. Dap an dung da duoc danh dau.');
        }

        // Highlight correct answer among all buttons
        for (const b of gridEl.querySelectorAll('.choice-btn')) {
          const bChoice = choices.find(
            (c) => (c.text ?? c.label ?? c.id) === b.textContent,
          );
          if (bChoice && bChoice.id === correctId) b.classList.add('correct');
          b.disabled = true;
        }

        finishBtn.classList.remove('hidden');
      });

      gridEl.appendChild(btn);
    }

    setStatus('Click vao dap an de chon.');
  }

  // â”€â”€ DRAG_DROP â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  function renderDragDrop(payload) {
    const prompt = typeof payload.prompt === 'string' ? payload.prompt : '';
    const items = Array.isArray(payload.items) ? payload.items : [];
    const dropZones = Array.isArray(payload.dropZones) ? payload.dropZones : [];
    state.ddTotalItems = items.length;

    const promptEl = document.createElement('div');
    promptEl.className = 'dd-prompt';
    promptEl.textContent = prompt;
    gameContainerEl.appendChild(promptEl);

    const hintEl = document.createElement('div');
    hintEl.className = 'dd-hint';
    hintEl.textContent =
      'Chon mot muc (danh sach duoi) roi click vung tuong ung (ben tren) de ghep noi.';
    gameContainerEl.appendChild(hintEl);

    // Drop zones row (top)
    const zonesEl = document.createElement('div');
    zonesEl.className = 'dd-zones';
    gameContainerEl.appendChild(zonesEl);

    // Items row (bottom)
    const itemsEl = document.createElement('div');
    itemsEl.className = 'dd-items';
    gameContainerEl.appendChild(itemsEl);

    const scoreEl = document.createElement('div');
    scoreEl.className = 'dd-score';
    scoreEl.textContent = `Ghep dung: 0 / ${items.length}`;
    gameContainerEl.appendChild(scoreEl);

    const finishBtn = document.createElement('button');
    finishBtn.className = 'btn-finish hidden';
    finishBtn.textContent = 'Ket thuc phien choi';
    finishBtn.addEventListener('click', () => {
      const finalScore = Math.round((state.ddScore / Math.max(items.length, 1)) * 100);
      void saveGameResult(finalScore, {
        mode: 'drag_drop',
        matched: state.ddMatched,
        correct: state.ddScore,
        total: items.length,
      });
    });
    gameContainerEl.appendChild(finishBtn);

    // Render drop zones
    for (const zone of dropZones) {
      const zoneEl = document.createElement('div');
      zoneEl.className = 'zone-box';
      zoneEl.dataset.zoneId = zone.id;
      zoneEl.dataset.acceptsItemId = zone.acceptsItemId ?? '';
      zoneEl.textContent = zone.label ?? zone.id;

      zoneEl.addEventListener('click', () => {
        if (!state.ddSelectedItemId) {
          setStatus('Hay chon mot muc truoc.');
          return;
        }

        const selectedId = state.ddSelectedItemId;
        if (state.ddMatched[selectedId] !== undefined) return;

        const acceptsItemId = zoneEl.dataset.acceptsItemId;
        const isCorrect = acceptsItemId === selectedId;

        // Clear selection
        for (const b of itemsEl.querySelectorAll('.item-btn')) {
          b.classList.remove('selected');
        }
        state.ddSelectedItemId = null;

        if (isCorrect) {
          state.ddMatched[selectedId] = zone.id;
          state.ddScore += 1;
          zoneEl.classList.add('matched-correct');

          // Disable matched item
          for (const b of itemsEl.querySelectorAll('.item-btn')) {
            if (b.dataset.itemId === selectedId) {
              b.disabled = true;
              b.classList.add('matched');
            }
          }

          scoreEl.textContent = `Ghep dung: ${state.ddScore} / ${items.length}`;
          setStatus('Ghep dung!');

          if (state.ddScore === items.length) {
            setStatus('Hoan thanh! Tat ca da duoc ghep noi dung.');
            finishBtn.classList.remove('hidden');
          }
        } else {
          zoneEl.classList.add('flash-wrong');
          setTimeout(() => zoneEl.classList.remove('flash-wrong'), 600);
          setStatus('Sai vung. Thu lai!');
        }
      });

      zonesEl.appendChild(zoneEl);
    }

    // Render draggable items
    for (const item of items) {
      const itemEl = document.createElement('button');
      itemEl.className = 'item-btn';
      itemEl.dataset.itemId = item.id;
      itemEl.textContent = item.label ?? item.id;

      itemEl.addEventListener('click', () => {
        if (itemEl.disabled) return;
        if (state.ddSelectedItemId === item.id) {
          state.ddSelectedItemId = null;
          itemEl.classList.remove('selected');
          setStatus('Bo chon.');
        } else {
          state.ddSelectedItemId = item.id;
          for (const b of itemsEl.querySelectorAll('.item-btn')) {
            b.classList.remove('selected');
          }
          itemEl.classList.add('selected');
          setStatus(
            `Da chon: "${item.label ?? item.id}". Bay gio click vung tuong ung ben tren.`,
          );
        }
      });

      itemsEl.appendChild(itemEl);
    }

    setStatus('Chon mot muc de bat dau ghep noi.');
  }

  // â”€â”€ SNAKE_DUEL â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  function renderSnakeDuel(payload) {
    const questions = Array.isArray(payload.questions) ? payload.questions : [];

    if (questions.length === 0) {
      const msgEl = document.createElement('p');
      msgEl.textContent = 'Khong co cau hoi nao cho Snake Duel.';
      gameContainerEl.appendChild(msgEl);
      return;
    }

    const legendEl = document.createElement('div');
    legendEl.className = 'sd-legend';
    legendEl.innerHTML =
      '<span class="p1">Nguoi choi 1 (Do): phim 1 2 3 4</span>' +
      '&nbsp;|&nbsp;' +
      '<span class="p2">Nguoi choi 2 (Xanh): phim Q W E R</span>';
    gameContainerEl.appendChild(legendEl);

    const scoreboardEl = document.createElement('div');
    scoreboardEl.className = 'sd-scoreboard';
    gameContainerEl.appendChild(scoreboardEl);

    const questionEl = document.createElement('div');
    questionEl.className = 'sd-question';
    gameContainerEl.appendChild(questionEl);

    const choicesEl = document.createElement('div');
    choicesEl.className = 'sd-choices';
    gameContainerEl.appendChild(choicesEl);

    const feedbackEl = document.createElement('div');
    feedbackEl.className = 'sd-feedback';
    gameContainerEl.appendChild(feedbackEl);

    const finishBtn = document.createElement('button');
    finishBtn.className = 'btn-finish hidden';
    finishBtn.textContent = 'Ket thuc tro choi';
    finishBtn.addEventListener('click', () => {
      if (state.sdKeyHandler) {
        window.removeEventListener('keydown', state.sdKeyHandler);
        state.sdKeyHandler = null;
      }
      void saveGameResult(state.sdP1Score + state.sdP2Score, {
        mode: 'snake_duel',
        p1Score: state.sdP1Score,
        p2Score: state.sdP2Score,
        totalQuestions: questions.length,
      });
    });
    gameContainerEl.appendChild(finishBtn);

    const P1_KEYS = ['1', '2', '3', '4'];
    const P2_KEYS = ['q', 'w', 'e', 'r'];

    function updateScoreboard() {
      scoreboardEl.innerHTML =
        `<span class="p1">P1: ${state.sdP1Score} diem</span>` +
        `&nbsp;&nbsp;&nbsp;` +
        `<span class="p2">P2: ${state.sdP2Score} diem</span>` +
        `&nbsp;&nbsp;&nbsp;Cau ${Math.min(state.sdQuestionIndex + 1, questions.length)} / ${questions.length}`;
    }

    function highlightCorrect(correctId) {
      for (const row of choicesEl.querySelectorAll('.sd-choice-row')) {
        if (row.dataset.choiceId === correctId) row.classList.add('correct');
      }
    }

    function showQuestion(index) {
      const q = questions[index];

      if (!q) {
        // All questions done
        questionEl.textContent = 'Tat ca cau hoi da hoan thanh!';
        choicesEl.innerHTML = '';
        const winner =
          state.sdP1Score > state.sdP2Score
            ? 'Nguoi choi 1 (Do) thang!'
            : state.sdP2Score > state.sdP1Score
              ? 'Nguoi choi 2 (Xanh) thang!'
              : 'Hoa!';
        feedbackEl.innerHTML =
          `<strong>${winner}</strong>&nbsp;` +
          `<span class="p1">P1: ${state.sdP1Score}</span> | ` +
          `<span class="p2">P2: ${state.sdP2Score}</span>`;
        finishBtn.classList.remove('hidden');
        if (state.sdKeyHandler) {
          window.removeEventListener('keydown', state.sdKeyHandler);
          state.sdKeyHandler = null;
        }
        return;
      }

      state.sdP1Answered = false;
      state.sdP2Answered = false;
      feedbackEl.textContent = '';

      const qChoices = Array.isArray(q.choices) ? q.choices : [];
      questionEl.textContent = q.prompt ?? '';
      choicesEl.innerHTML = '';

      const keyLabels = ['1/Q', '2/W', '3/E', '4/R'];
      for (let i = 0; i < qChoices.length; i++) {
        const c = qChoices[i];
        const row = document.createElement('div');
        row.className = 'sd-choice-row';
        row.dataset.choiceId = c.id;
        row.innerHTML = `<span class="sd-label">${keyLabels[i] ?? i + 1}.</span>${c.text ?? c.id}`;
        choicesEl.appendChild(row);
      }

      updateScoreboard();
      setStatus('Nguoi choi 1: phim 1-4 | Nguoi choi 2: phim Q-R de chon dap an.');
    }

    function onKeyDown(e) {
      if (state.isFinished) return;
      const q = questions[state.sdQuestionIndex];
      if (!q) return;

      const key = e.key.toLowerCase();
      const qChoices = Array.isArray(q.choices) ? q.choices : [];

      let playerIndex = -1;
      let choiceIndex = -1;

      if (P1_KEYS.includes(key) && !state.sdP1Answered) {
        playerIndex = 1;
        choiceIndex = P1_KEYS.indexOf(key);
      } else if (P2_KEYS.includes(key) && !state.sdP2Answered) {
        playerIndex = 2;
        choiceIndex = P2_KEYS.indexOf(key);
      } else {
        return;
      }

      const chosen = qChoices[choiceIndex];
      if (!chosen) return;

      const isCorrect = chosen.id === q.correctChoiceId;

      if (playerIndex === 1) {
        state.sdP1Answered = true;
        if (isCorrect) {
          state.sdP1Score += 100;
          feedbackEl.innerHTML += `<span class="p1">P1 dung! (+100)</span> `;
        } else {
          feedbackEl.innerHTML += `<span class="p1 wrong">P1 sai.</span> `;
        }
      } else {
        state.sdP2Answered = true;
        if (isCorrect) {
          state.sdP2Score += 100;
          feedbackEl.innerHTML += `<span class="p2">P2 dung! (+100)</span> `;
        } else {
          feedbackEl.innerHTML += `<span class="p2 wrong">P2 sai.</span> `;
        }
      }

      updateScoreboard();

      // Advance when both players have answered
      if (state.sdP1Answered && state.sdP2Answered) {
        highlightCorrect(q.correctChoiceId);
        state.sdQuestionIndex += 1;
        setTimeout(() => showQuestion(state.sdQuestionIndex), 1800);
      }
    }

    state.sdKeyHandler = onKeyDown;
    window.addEventListener('keydown', onKeyDown);
    showQuestion(0);
  }

  // â”€â”€ Dispatch â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  function renderGame(gameData) {
    gameContainerEl.innerHTML = '';

    if (!gameData || !gameData.payload) {
      const msgEl = document.createElement('p');
      msgEl.textContent = 'Khong tim thay du lieu game trong file .eduvi.';
      gameContainerEl.appendChild(msgEl);
      setStatus('Loi: Khong co du lieu payload.');
      return;
    }

    const { templateId, scene, payload } = gameData;

    const titleEl = document.createElement('h2');
    titleEl.className = 'game-title';
    titleEl.textContent = scene?.title ?? templateId;
    gameContainerEl.appendChild(titleEl);

    const badge = document.createElement('div');
    badge.className = 'template-badge';
    badge.textContent = templateId;
    gameContainerEl.appendChild(badge);

    if (templateId === 'HOVER_SELECT') {
      renderHoverSelect(payload);
    } else if (templateId === 'DRAG_DROP') {
      renderDragDrop(payload);
    } else if (templateId === 'SNAKE_DUEL') {
      renderSnakeDuel(payload);
    } else {
      const msgEl = document.createElement('p');
      msgEl.textContent = `Template khong duoc ho tro offline: ${templateId}`;
      gameContainerEl.appendChild(msgEl);
    }
  }

  // â”€â”€ Bootstrap â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  async function bootstrap() {
    try {
      state.contract = await window.eduviGameApi.readLaunchContract();
      const sourceEduvi = await window.eduviGameApi.readSourceEduvi();
      state.gameData = extractGameData(sourceEduvi);

      const templateId = state.gameData?.templateId ?? 'N/A';
      metaEl.textContent =
        `Session: ${state.contract.sessionId} | Template: ${templateId} | Mode: ${state.contract.mode}`;
      log('Launch contract loaded. Offline runtime ready.');

      if (!state.gameData) {
        const msgEl = document.createElement('p');
        msgEl.textContent = 'Khong doc duoc du lieu game tu file .eduvi.';
        gameContainerEl.appendChild(msgEl);
        setStatus('Loi: Khong co du lieu game.');
        return;
      }

      renderGame(state.gameData);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      metaEl.textContent = `Runtime initialization failed: ${message}`;
      log(`Error: ${message}`);
    }
  }

  void bootstrap();
})();

