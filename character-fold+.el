;;; character-fold+.el --- Extensions to `character-fold.el'
;;
;; Filename: character-fold+.el
;; Description: Extensions to `character-fold.el'
;; Author: Drew Adams
;; Maintainer: Drew Adams
;; Copyright (C) 2015, Drew Adams, all rights reserved.
;; Created: Fri Nov 27 09:12:01 2015 (-0800)
;; Version: 0
;; Package-Requires: ()
;; Last-Updated: Fri Nov 27 10:02:42 2015 (-0800)
;;           By: dradams
;;     Update #: 28
;; URL: http://www.emacswiki.org/character-fold+.el
;; Doc URL: http://emacswiki.org/CharacterFoldPlus
;; Keywords: isearch, search, unicode
;; Compatibility: GNU Emacs: 25.x
;;
;; Features that might be required by this library:
;;
;;   None
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;
;;  Extensions to Isearch character folding.
;;
;;  Non-nil option `char-fold-symmetric' means that char folding is
;;  symmetric: When you search for any of an equivalence class of
;;  characters you find all of them.
;;
;;  The default value of `char-fold-symmetric' is `nil', which gives
;;  the same behavior as vanilla Emacs: you find all members of the
;;  equivalence class only when you search for the base character.
;;
;;  For example, with a `nil' value you can search for "e" (a base
;;  character) to find "é", but not vice versa.  With a non-`nil'
;;  value you can search for either to find itself and the other
;;  members of the equivalence class - the base char is not treated
;;  specially.
;;
;;  Example non-`nil' behavior:
;;
;;    Searching for any of these characters and character compositions
;;    in the search string finds all of them.  (Use `C-u C-x =' with
;;    point before a character to see complete information about it.)
;;
;;      e 𝚎 𝙚 𝘦 𝗲 𝖾 𝖊 𝕖 𝔢 𝓮 𝒆 𝑒 𝐞 ｅ ㋎ ㋍ ⓔ ⒠
;;      ⅇ ℯ ₑ ẽ ẽ ẻ ẻ ẹ ẹ ḛ ḛ ḙ ḙ ᵉ ȩ ȩ ȇ ȇ
;;      ȅ ȅ ě ě ę ę ė ė ĕ ĕ ē ē ë ë ê ê é é è è
;;
;;    An example of a composition is "é".  Searching for that finds
;;    the same matches as searching for "é" or searching for "e".
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Change Log:
;;
;; 2015/11/27 dadams
;;     Created.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at
;; your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Code:

(require 'character-fold)

;;;;;;;;;;;;;;;;;;;;;;;

(defvar char-fold-decomps ()
  "List of conses of a decomposition and its base char.")

(defun update-char-fold-table ()
  "Update the value of variable `character-fold-table'.
The new value reflects the current value of `char-fold-symmetric'."
  (setq char-fold-decomps  ())
  (setq character-fold-table
        (let* ((equiv  (make-char-table 'character-fold-table))
               (table  (unicode-property-table-internal 'decomposition))
               (func   (char-table-extra-slot table 1)))
          ;; Ensure that the table is populated.
          (map-char-table (lambda (ii vv) (when (consp ii) (funcall func (car ii) vv table))) table)
          ;; Compile a list of all complex chars that each simple char should match.
          (map-char-table
           (lambda (ii dec)
             (when (consp dec)
               (when (symbolp (car dec)) (setq dec  (cdr dec))) ; Discard a possible formatting tag.
               ;; Skip trivial cases like ?a decomposing to (?a).
               (unless (and (eq ii (car dec))  (null (cdr dec)))
                 (let ((dd           dec)
                       (fold-decomp  t)
                       kk found)
                   (while (and dd  (not found))
                     (setq kk  (pop dd))
                     ;; Is KK a number or letter, per unicode standard?
                     (setq found  (memq (get-char-code-property kk 'general-category)
                                        '(Lu Ll Lt Lm Lo Nd Nl No))))
                   (if found
                       ;; Check if the decomposition has more than one letter, because then
                       ;; we don't want the first letter to match the decomposition.
                       (dolist (kk  dd)
                         (when (and fold-decomp  (memq (get-char-code-property kk 'general-category)
                                                       '(Lu Ll Lt Lm Lo Nd Nl No)))
                           (setq fold-decomp  nil)))
                     ;; No number or letter on decomposition.  Take its first char.
                     (setq found  (car-safe dec)))
                   ;; Fold a multi-char decomposition only if at least one of the chars is
                   ;; non-spacing (combining).
                   (when fold-decomp
                     (setq fold-decomp  nil)
                     (dolist (kk  dec)
                       (when (and (not fold-decomp)
                                  (> (get-char-code-property kk 'canonical-combining-class) 0))
                         (setq fold-decomp  t))))
                   ;; Add II to the list of chars that KK can represent.  Maybe add its decomposition
                   ;; too, so we can match multi-char representations like (format "a%c" 769).
                   (when (and found  (not (eq ii kk)))
                     (let ((chr-strgs  (cons (char-to-string ii) (aref equiv kk))))
                       (aset equiv kk (if fold-decomp
                                          (cons (apply #'string dec) chr-strgs)
                                        chr-strgs))))))))
           table)
          ;; Add some manual entries.
          (dolist (it '((?\" "＂" "“" "”" "”" "„" "⹂" "〞" "‟" "‟" "❞" "❝"
                         "❠" "“" "„" "〝" "〟" "🙷" "🙶" "🙸" "«" "»")
                        (?' "❟" "❛" "❜" "‘" "’" "‚" "‛" "‚" "󠀢" "❮" "❯" "‹" "›")
                        (?` "❛" "‘" "‛" "󠀢" "❮" "‹")))
            (let ((idx        (car it))
                  (chr-strgs  (cdr it)))
              (aset equiv idx (append chr-strgs (aref equiv idx)))))

          ;; This is the essential bit added by `character-fold+.el'.
          (when char-fold-symmetric
            ;; Add an entry for each equivalent char.
            (let ((others  ()))
              (map-char-table
               (lambda (base vv)
                 (let ((chr-strgs  (aref equiv base)))
                   (when (consp chr-strgs)
                     (dolist (strg  (cdr chr-strgs))
                       (when (< (length strg) 2)
                         (push (cons (string-to-char strg) (remove strg chr-strgs)) others))
                       ;; Add it and its base char to `char-fold-decomps'.
                       (push (cons strg (char-to-string base)) char-fold-decomps)))))
               equiv)
              (dolist (it  others)
                (let ((base       (car it))
                      (chr-strgs  (cdr it)))
                  (aset equiv base (append chr-strgs (aref equiv base)))))))

          (map-char-table ; Convert the lists of characters we compiled into regexps.
           (lambda (ii vv) (let ((re  (regexp-opt (cons (char-to-string ii) vv))))
                        (if (consp ii) (set-char-table-range equiv ii re) (aset equiv ii re))))
           equiv)
          equiv)))

(defadvice character-fold-to-regexp (before replace-decompositions activate)
  "Replace any decompositions in `character-fold-table' by their base chars.
This allows search to match all equivalents."
  (when char-fold-decomps
    (dolist (decomp  char-fold-decomps)
      (ad-set-arg 0  (replace-regexp-in-string (regexp-quote (car decomp)) (cdr decomp)
                                               (ad-get-arg 0) 'FIXED-CASE 'LITERAL)))))

(defcustom char-fold-symmetric nil
  "Non-nil means char-fold searching treats equivalent chars the same.
That is, use of any of a set of char-fold equivalent chars in a search
string finds any of them in the text being searched.

If nil then only the \"base\" or \"canonical\" char of the set matches
any of them.  The others match only themselves, even when char-folding
is turned on."
  :set (lambda (sym defs)
         (custom-set-default sym defs)
         (update-char-fold-table))
  :type 'boolean :group 'isearch)

;;;;;;;;;;;;;;;;;;;;;;;

(provide 'character-fold+)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; character-fold+.el ends here
