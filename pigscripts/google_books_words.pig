/*
 * Finds word frequencies (probability that a random word is the given word) using the Google Books corpus.
 */

-- This script is set up to run against a portion of the data (words beginning with "q") for testing purposes.
-- To run against the full data set, you can set INPUT_PATH to
-- 's3://mortar-example-data/ngrams/books/20120701/eng-all/1gram/*.gz'

%default INPUT_PATH 's3://mortar-example-data/ngrams/books/20120701/eng-all/1gram/googlebooks-eng-all-1gram-20120701-q.gz'
%default OUTPUT_PATH 's3://mortar-example-output-data/$MORTAR_EMAIL_S3_ESCAPED/1gram'

-- Timeframe to take word occurrences from
-- The Google Books Ngrams V2 dataset has data up to 2008

%default START_YEAR '2004'
%default END_YEAR '9999'

-- Load the word occurrence data

words           =   LOAD '$INPUT_PATH' USING PigStorage('\t') AS (word: chararray, year: int, occurrences: int);

-- Filter out years outside of the specified timeframe
-- Filter out words that have non-letter characters in them

filtered_words  =   FILTER words BY (
                        year >= $START_YEAR AND 
                        year <= $END_YEAR AND 
                        word matches '^[A-Za-z]+$'
                    );

-- Ignore case, combining the occurrences of different capitalizations of the same word
-- ex. "quantity", "Quantity", and "QUANTITY" all get combined

words_lower_with_dups   =   FOREACH filtered_words GENERATE LOWER(word) AS word, year, occurrences;
words_lower_grouped     =   GROUP words_lower_with_dups BY (word, year);
words_lower             =   FOREACH words_lower_grouped GENERATE 
                                group.word AS word, 
                                group.year AS year, 
                                SUM(words_lower_with_dups.occurrences) AS occurrences;

-- Get the number of occurrences for each word over the entire timeframe

words_lower_over_time   =   GROUP words_lower BY word;
word_totals             =   FOREACH words_lower_over_time GENERATE 
                                group AS word, 
                                SUM(words_lower.occurrences) AS occurrences;

-- Find the word frequencies (probability that a random word is the given word)
-- by normalizing the occurrences column against the total number of occurrences

all_word_totals         =   GROUP word_totals ALL;
stats                   =   FOREACH all_word_totals GENERATE 
                                COUNT(word_totals) AS num_unique_words,
                                SUM(word_totals.occurrences) AS total_num_words;

word_frequencies        =   FOREACH word_totals GENERATE 
                                word AS word, 
                                occurrences AS occurrences, 
                                (double)occurrences / (double)stats.total_num_words AS frequency: double;
word_frequencies_sorted =   ORDER word_frequencies BY frequency DESC;

rmf $OUTPUT_PATH/dictionary;
STORE word_frequencies_sorted INTO '$OUTPUT_PATH/dictionary' USING PigStorage('\t');
