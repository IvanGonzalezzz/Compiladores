#include "analyzer.h"
#include <stdlib.h>
#include <string.h>

/**
 * @brief Finds a terminal identifier by terminal name.
 * @param g Parsed grammar.
 * @param name Terminal name to search.
 * @return Terminal id if found, otherwise -1.
 */
static int find_terminal_id(const grammar *g, const char *name)
{
	// TODO: Validate inputs and search terminal list to return the matching terminal id.
	if (!g || !name)
		return -1;

	for (int i = 0; i < g->num_terminals; i++)
	{
		if (strcmp(g->terminals[i].symbol, name) == 0)
			return i;
	}

	return -1;
}

/**
 * @brief Appends one symbol to a dynamically sized symbol array.
 * @param arr Target array pointer.
 * @param count Current element count; incremented on success.
 * @param text Symbol text to copy.
 * @param is_terminal Indicates terminal/non-terminal role.
 * @return true on success, false on allocation failure.
 */
static bool add_symbol_to_array(symbol **arr, int *count, const char *text, bool is_terminal)
{
	// TODO: Reallocate the array, duplicate symbol text, fill metadata, and increase count.
	symbol *tmp = realloc(*arr, (*count + 1) * sizeof(symbol));
	if (!tmp)
		return false;

	*arr = tmp;

	(*arr)[*count].symbol = strdup(text);
	(*arr)[*count].symbol_length = strlen(text);
	(*arr)[*count].is_terminal = is_terminal;

	(*count)++;

	return true;
}

/**
 * @brief Builds FIRST and nullable tables for all non-terminals.
 * @param g Parsed grammar.
 * @param first_table Output flattened table: non-terminal x terminal.
 * @param nullable Output nullable flags per non-terminal.
 * @param epsilon_id Output id of terminal "epsilon", or -1 if absent.
 * @return true when tables were built, false on invalid input or allocation error.
 */
static bool compute_first_tables(const grammar *g, bool **first_table, bool **nullable, int *epsilon_id)
{
	// TODO: Allocate FIRST/nullable tables and compute them with fixed-point propagation over productions.
	if (!g || !first_table || !nullable || !epsilon_id)
		return false;

	int N = g->num_non_terminals;
	int T = g->num_terminals;

	*epsilon_id = find_terminal_id(g, "epsilon");

	*first_table = calloc(N * T, sizeof(bool));
	*nullable = calloc(N, sizeof(bool));

	if (!*first_table || !*nullable)
		return false;

	bool changed = true;

	while (changed)
	{
		changed = false;

		for (int p = 0; p < g->num_productions; p++)
		{
			production prod = g->productions[p];
			int A = prod.non_terminal_id;

			bool all_nullable = true;

			for (int i = 0; i < prod.production_length; i++)
			{
				int sym_id = prod.production_symbol_ids[i];

				if (sym_id < T)
				{
					if (sym_id != *epsilon_id)
					{
						if (!(*first_table)[A * T + sym_id])
						{
							(*first_table)[A * T + sym_id] = true;
							changed = true;
						}
					}

					if (sym_id != *epsilon_id)
					{
						all_nullable = false;
						break;
					}
				}
				else
				{
					int B = sym_id - T;

					for (int t = 0; t < T; t++)
					{
						if (t == *epsilon_id)
							continue;

						if ((*first_table)[B * T + t] &&
							!(*first_table)[A * T + t])
						{
							(*first_table)[A * T + t] = true;
							changed = true;
						}
					}

					if (!(*nullable)[B])
					{
						all_nullable = false;
						break;
					}
				}
			}

			if (all_nullable)
			{
				if (!(*nullable)[A])
				{
					(*nullable)[A] = true;
					changed = true;
				}
			}
		}
	}

	return true;
}

/**
 * @brief Builds FOLLOW table for all non-terminals.
 * @param g Parsed grammar.
 * @param first_table FIRST table from compute_first_tables.
 * @param nullable Nullable flags from compute_first_tables.
 * @param epsilon_id Terminal id for "epsilon", or -1.
 * @param out_follow Output flattened table: non-terminal x (terminals + '$').
 * @param out_follow_cols Output number of columns for out_follow.
 * @return true on success, false on allocation error or invalid input.
 */
static bool compute_follow_table(
	const grammar *g,
	const bool *first_table,
	const bool *nullable,
	int epsilon_id,
	bool **out_follow,
	int *out_follow_cols)
{
	if (!g || !first_table || !nullable || !out_follow || !out_follow_cols)
		return false;

	int N = g->num_non_terminals;
	int T = g->num_terminals;

	int cols = T + 1; 
	*out_follow_cols = cols;

	*out_follow = calloc(N * cols, sizeof(bool));
	if (!*out_follow)
		return false;

	int dollar_col = T;

	
	(*out_follow)[0 * cols + dollar_col] = true;

	bool changed = true;

	while (changed)
	{
		changed = false;

		for (int p = 0; p < g->num_productions; p++)
		{
			production prod = g->productions[p];
			int A = prod.non_terminal_id;

			for (int i = 0; i < prod.production_length; i++)
			{
				int sym_id = prod.production_symbol_ids[i];

				
				if (sym_id >= T)
				{
					int B = sym_id - T;
					bool nullable_suffix = true;

					
					for (int j = i + 1; j < prod.production_length; j++)
					{
						int next_id = prod.production_symbol_ids[j];

						if (next_id < T) 
						{
							if (next_id != epsilon_id)
							{
								if (!(*out_follow)[B * cols + next_id])
								{
									(*out_follow)[B * cols + next_id] = true;
									changed = true;
								}
							}
							nullable_suffix = false;
							break;
						}
						else
						{
							int C = next_id - T;

							for (int t = 0; t < T; t++)
							{
								if (t == epsilon_id)
									continue;

								if (first_table[C * T + t] &&
									!(*out_follow)[B * cols + t])
								{
									(*out_follow)[B * cols + t] = true;
									changed = true;
								}
							}

							if (!nullable[C])
							{
								nullable_suffix = false;
								break;
							}
						}
					}

					if (nullable_suffix)
					{
						for (int t = 0; t < cols; t++)
						{
							if ((*out_follow)[A * cols + t] &&
								!(*out_follow)[B * cols + t])
							{
								(*out_follow)[B * cols + t] = true;
								changed = true;
							}
						}
					}
				}
			}
		}
	}

	return true;
}

/**
 * @brief Collects FIRST symbols for one non-terminal from the computed table.
 * @param g Parsed grammar.
 * @param non_terminal_id Non-terminal index.
 * @param first_table FIRST table.
 * @param nullable Nullable flags.
 * @param epsilon_id Terminal id for "epsilon", or -1.
 * @param out_first Output array with FIRST symbols.
 * @return Number of collected symbols, or 0 on error.
 */
static int collect_first_for_non_terminal(
	const grammar *g,
	int non_terminal_id,
	const bool *first_table,
	const bool *nullable,
	int epsilon_id,
	symbol **out_first)
{
	// TODO: Read one FIRST row, append terminal symbols, and include epsilon when nullable.
	if (!g || !first_table || !out_first)
		return 0;

	int count = 0;
	int T = g->num_terminals;

	for (int t = 0; t < T; t++)
	{
		if (first_table[non_terminal_id * T + t])
		{
			add_symbol_to_array(out_first, &count,
								g->terminals[t].symbol, true);
		}
	}

	if (nullable[non_terminal_id] && epsilon_id >= 0)
	{
		add_symbol_to_array(out_first, &count,
							g->terminals[epsilon_id].symbol, true);
	}

	return count;
}

/**
 * @brief Collects FOLLOW symbols for one non-terminal from the computed table.
 * @param g Parsed grammar.
 * @param non_terminal_id Non-terminal index.
 * @param follow_table FOLLOW table.
 * @param follow_cols Number of columns in follow_table.
 * @param out_follow Output array with FOLLOW symbols.
 * @return Number of collected symbols, or 0 on error.
 */
static int collect_follow_for_non_terminal(
	const grammar *g,
	int non_terminal_id,
	const bool *follow_table,
	int follow_cols,
	symbol **out_follow)
{
	if (!g || !follow_table || !out_follow)
		return 0;

	int count = 0;
	int T = g->num_terminals;

	for (int t = 0; t < T; t++)
	{
		if (follow_table[non_terminal_id * follow_cols + t])
		{
			add_symbol_to_array(out_follow, &count,
								g->terminals[t].symbol, true);
		}
	}

	if (follow_table[non_terminal_id * follow_cols + T])
	{
		add_symbol_to_array(out_follow, &count, "$", true);
	}

	return count;
}

/**
 * @brief Computes FIRST set for one non-terminal by index.
 * @param g Parsed grammar.
 * @param non_terminal_id Non-terminal index in g->non_terminals.
 * @param out_first Output array with FIRST symbols.
 * @return Number of symbols in out_first, or 0 on error.
 */
int compute_first_for_non_terminal(const grammar *g, int non_terminal_id, symbol **out_first)
{
	// TODO: Validate inputs, compute shared FIRST tables, and collect FIRST for the requested non-terminal.
	if (!g || !out_first)
		return 0;

	bool *first_table = NULL;
	bool *nullable = NULL;
	int epsilon_id;

	if (!compute_first_tables(g, &first_table, &nullable, &epsilon_id))
		return 0;

	int result = collect_first_for_non_terminal(
		g,
		non_terminal_id,
		first_table,
		nullable,
		epsilon_id,
		out_first);

	free(first_table);
	free(nullable);

	return result;
}

/**
 * @brief Computes FOLLOW set for one non-terminal by index.
 * @param g Parsed grammar.
 * @param non_terminal_id Non-terminal index in g->non_terminals.
 * @param out_follow Output array with FOLLOW symbols.
 * @return Number of symbols in out_follow, or 0 on error.
 */
int compute_follow_for_non_terminal(const grammar *g, int non_terminal_id, symbol **out_follow)
{
	if (!g || !out_follow)
		return 0;

	bool *first_table = NULL;
	bool *nullable = NULL;
	bool *follow_table = NULL;

	int epsilon_id;
	int follow_cols;

	if (!compute_first_tables(g, &first_table, &nullable, &epsilon_id))
		return 0;

	if (!compute_follow_table(g, first_table, nullable, epsilon_id,
							 &follow_table, &follow_cols))
	{
		free(first_table);
		free(nullable);
		return 0;
	}

	int result = collect_follow_for_non_terminal(
		g,
		non_terminal_id,
		follow_table,
		follow_cols,
		out_follow);

	free(first_table);
	free(nullable);
	free(follow_table);

	return result;
}

/**
 * @brief Computes FIRST set for the start symbol.
 * @param g Parsed grammar.
 * 
 * @param out_first Output array with FIRST(start) terminals.
 * @return Number of symbols in out_first, or 0 on error.
 */
int compute_first_for_start_symbol(const grammar *g, symbol **out_first)
{
	// TODO: Delegate FIRST computation to the generic non-terminal function using the start-symbol index.
	if (!g)
		return 0;

	return compute_first_for_non_terminal(g, 0, out_first);
}

/**
 * @brief Computes FOLLOW set for the start symbol.
 * @param g Parsed grammar.
 * @param out_follow Output array with FOLLOW(start) terminals.
 * @return Number of symbols in out_follow, or 0 on error.
 */
int compute_follow_for_start_symbol(const grammar *g, symbol **out_follow)
{
	if (!g)
		return 0;

	return compute_follow_for_non_terminal(g, 0, out_follow);
}

/**
 * @brief Frees a symbol array and each duplicated symbol string.
 * @param symbols Symbol array to release.
 * @param count Number of initialized entries.
 * @return This function does not return a value.
 */
void free_symbol_array(symbol *symbols, int count)
{
	if (!symbols)
		return;

	for (int i = 0; i < count; i++)
	{
		free(symbols[i].symbol);
	}

	free(symbols);
}
