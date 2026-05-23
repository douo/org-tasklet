EMACS ?= emacs
ELS = org-tasklet-core.el org-tasklet.el org-tasklet-capture.el org-tasklet-agenda.el org-tasklet-project.el org-tasklet-archive.el org-tasklet-triage.el org-tasklet-protocol.el
LOAD_NEWER = --eval "(setq load-prefer-newer t)"

.PHONY: test compile native-compile measure clean

test:
	$(EMACS) -Q --batch -L . $(LOAD_NEWER) -l test/org-tasklet-test.el -f ert-run-tests-batch-and-exit

compile:
	$(EMACS) -Q --batch -L . $(LOAD_NEWER) -f batch-byte-compile $(ELS)

native-compile:
	$(EMACS) -Q --batch -L . $(LOAD_NEWER) -f batch-native-compile $(ELS)

measure:
	$(EMACS) -Q --batch -L . $(LOAD_NEWER) --eval "(let ((before (length features)) (start (float-time))) (require 'org-tasklet) (princ (format \"require-org-tasklet=%.3fs\nfeatures-added=%d\nloaded-org=%S\nloaded-org-agenda=%S\nloaded-org-capture=%S\nloaded-org-protocol=%S\n\" (- (float-time) start) (- (length features) before) (featurep 'org) (featurep 'org-agenda) (featurep 'org-capture) (featurep 'org-protocol))))"

clean:
	rm -f *.elc
