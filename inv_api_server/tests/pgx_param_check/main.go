package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

func main() {
	root := os.Args[1]
	fset := token.NewFileSet()
	issues := 0

	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() || !strings.HasSuffix(path, ".go") {
			return nil
		}
		if strings.Contains(path, "_test.go") || strings.Contains(path, "pgx_param_check") {
			return nil
		}

		f, err := parser.ParseFile(fset, path, nil, 0)
		if err != nil {
			return nil
		}

		ast.Inspect(f, func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok {
				return true
			}

			// Check if this is a db.Query, db.QueryRow, or db.Exec call
			sel, ok := call.Fun.(*ast.SelectorExpr)
			if !ok {
				return true
			}
			method := sel.Sel.Name
			if method != "Query" && method != "QueryRow" && method != "Exec" {
				return true
			}

			// Need at least 2 args: ctx, sql
			if len(call.Args) < 2 {
				return true
			}

			// Get the SQL string (second argument)
			sqlArg := call.Args[1]
			sqlStr := extractString(sqlArg)
			if sqlStr == "" {
				return true // dynamic SQL, skip
			}

			// Count max $N placeholder
			maxParam := maxPlaceholder(sqlStr)
			if maxParam == 0 {
				return true // no placeholders
			}

			// Count actual arguments (after ctx and sql)
			actualArgs := len(call.Args) - 2

			// Check if last arg is variadic (args...)
			lastArg := call.Args[len(call.Args)-1]
			if isEllipsis(lastArg) {
				return true // variadic, can't statically check
			}

			if actualArgs != maxParam {
				pos := fset.Position(call.Pos())
				relPath, _ := filepath.Rel(root, path)
				fmt.Printf("MISMATCH: %s:%d  %s()  SQL expects $%d but got %d args\n",
					relPath, pos.Line, method, maxParam, actualArgs)
				fmt.Printf("  SQL: %s\n", truncate(sqlStr, 120))
				issues++
			}

			return true
		})
		return nil
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "walk error: %v\n", err)
	}

	fmt.Printf("\n=== Scan complete: %d issues found ===\n", issues)
}

func extractString(expr ast.Expr) string {
	switch e := expr.(type) {
	case *ast.BasicLit:
		if e.Kind == token.STRING {
			s, _ := strconv.Unquote(e.Value)
			return s
		}
	}
	return ""
}

func maxPlaceholder(sql string) int {
	re := regexp.MustCompile(`\$(\d+)`)
	matches := re.FindAllStringSubmatch(sql, -1)
	max := 0
	for _, m := range matches {
		n, _ := strconv.Atoi(m[1])
		if n > max {
			max = n
		}
	}
	return max
}

func isEllipsis(expr ast.Expr) bool {
	_, ok := expr.(*ast.Ellipsis)
	return ok
}

func truncate(s string, maxLen int) string {
	s = strings.ReplaceAll(s, "\n", " ")
	s = strings.ReplaceAll(s, "\t", " ")
	for strings.Contains(s, "  ") {
		s = strings.ReplaceAll(s, "  ", " ")
	}
	if len(s) > maxLen {
		return s[:maxLen] + "..."
	}
	return s
}
