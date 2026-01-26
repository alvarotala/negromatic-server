document.addEventListener('DOMContentLoaded', function() {
  const initAiAssistant = () => {
    const applyBtn = document.getElementById('apply-ai-btn');
    if (!applyBtn) return;

    // Use data attributes to find target elements if they exist, otherwise fallback to defaults
    const targetSelector = applyBtn.getAttribute('data-target') || '#content';
    const instructionSelector = applyBtn.getAttribute('data-instruction') || '#ai-instruction';
    const endpoint = applyBtn.getAttribute('data-endpoint') || '/api/ai/strategy_edit';

    const contentArea = document.querySelector(targetSelector);
    const instructionArea = document.querySelector(instructionSelector);
    const btnText = document.getElementById('ai-btn-text');
    const loader = document.getElementById('ai-loader');
    
    // Modal elements
    const diffModal = new bootstrap.Modal(document.getElementById('aiDiffModal'));
    const diffContainer = document.getElementById('ai-diff-container');
    const confirmApplyBtn = document.getElementById('confirm-ai-apply');
    let pendingContent = '';

    if (!contentArea || !instructionArea) {
      console.warn('AI Assistant: Target or instruction area not found', { targetSelector, instructionSelector });
      return;
    }

    const generateDiff = (oldText, newText) => {
      const diff = Diff.diffLines(oldText, newText);
      let html = '';
      
      diff.forEach((part) => {
        const colorClass = part.added ? 'diff-added' :
                           part.removed ? 'diff-removed' : 'diff-unchanged';
        const prefix = part.added ? '+ ' : part.removed ? '- ' : '  ';
        
        // Escape HTML
        const text = part.value.replace(/&/g, '&amp;')
                               .replace(/</g, '&lt;')
                               .replace(/>/g, '&gt;');
        
        // Split into lines to apply prefix to each
        const lines = text.split(/\r?\n/);
        if (lines[lines.length - 1] === '') lines.pop();
        
        lines.forEach(line => {
          html += `<div class="${colorClass}">${prefix}${line}</div>`;
        });
      });
      
      return html;
    };

    confirmApplyBtn.addEventListener('click', () => {
      if (!pendingContent) return;
      contentArea.value = pendingContent;
      contentArea.focus();
      
      instructionArea.value = ''; // Clear prompt
      pendingContent = ''; // Clear pending
      diffModal.hide();
    });

    applyBtn.addEventListener('click', async function() {
      const instruction = instructionArea.value.trim();
      if (!instruction) return alert('Please enter an instruction first.');

      pendingContent = '';

      applyBtn.disabled = true;
      loader.classList.remove('d-none');
      if (btnText) btnText.textContent = 'Processing...';

      try {
        const response = await fetch(endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            current_content: contentArea.value,
            instruction: instruction
          })
        });

        const data = await response.json();

        if (data.success) {
          pendingContent = data.content;
          diffContainer.innerHTML = generateDiff(contentArea.value, data.content);
          diffModal.show();
        } else {
          alert('AI Error: ' + (data.error || 'Unknown error'));
        }
      } catch (error) {
        console.error('AI Request failed:', error);
        alert('Network error occurred.');
      } finally {
        applyBtn.disabled = false;
        loader.classList.add('d-none');
        if (btnText) btnText.textContent = 'Apply with AI';
      }
    });
  };

  initAiAssistant();
});
