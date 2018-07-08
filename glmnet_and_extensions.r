
#https://www.kaggle.com/captcalculator/stock-prediction-with-r-glmnet-and-tm-packages

library(tm)
library(RWeka)
library(magrittr)
library(Matrix)
library(glmnet)
library(ROCR)
library(ggplot2)
# Read in the data
data <- read.csv('/home/terrence/CODING/Python/MODELS/Neural_Nets_in_R/Combined_News_DJIA.csv', stringsAsFactors = FALSE)

#First, we will clean up the data and do some quick preprocessing. I am also going to add a '<\\s>' token between the headlines. We don't want the last word of a headline and the first word of the next to be counted as a bigram.

# Make 'Date' column a Date object to make train/test splitting easier
data$Date <- as.Date(data$Date)
dim(data)
names(data)
data[c(1:3),]

# Combine headlines into one text blob for each day and add sentence separation token
data$all <- paste(data$Top1, data$Top2, data$Top3, data$Top4, data$Top5, data$Top6,
                  data$Top7, data$Top8, data$Top9, data$Top10, data$Top11, data$Top12, 
                  data$Top13, data$Top14, data$Top15, data$Top16, data$Top17, data$Top18,
                  data$Top19, data$Top20, data$Top21, data$Top22, data$Top23, data$Top24,
                  data$Top25, sep=' <s> ')
                  

dim(data)
names(data)

# Get rid of those pesky b's and backslashes 
data$all <- gsub('b"|b\'|\\\\|\\"', "", data$all)

# Get rid of all punctuation except headline separators
data$all <- gsub("([<>])|[[:punct:]]", "\\1", data$all)

# Reduce to only the three columns we need. 
data <- data[, c('Date', 'Label', 'all')]

dim(data)
names(data)

#Now I am going to convert the text headlines into a document-term matrix via a Corpus object using tm. Each row of the document-term matrix will be the combined headlines for each day. Columns will be frequency counts of unigrams. The control object will tell the DocumentTermMatrix() function what we want to do with the text before converting to a term matrix. Punctuation and numbers are removed, everything is converted to lowercase, and common words are removed since they will likely have little predictive power. 

control <- list(
  removeNumbers = TRUE,
  tolower = TRUE,
  # exclude stopwords and headline tokens
  stopwords = c(stopwords(kind = 'SMART'), '<s>')
)


dtm <- Corpus(VectorSource(data$all)) %>% 
  DocumentTermMatrix(control=control)


#Now we split the data into train and test sets as suggested in the data description.

split_index <- data$Date <= '2014-12-31'


ytrain <- as.factor(data$Label[split_index])
xtrain <- Matrix(as.matrix(dtm)[split_index, ], sparse=TRUE)

ytest <- as.factor(data$Label[!split_index])
xtest <- Matrix(as.matrix(dtm)[!split_index, ], sparse=TRUE)

#Now we can fit a glmnet model using ridge regression. Here I do so using cross-validation to select the best lambda value. Then predictions are made. We are predicting probabilities in this case. 
#WHen we predict we use the lambda value returned by our cross-validation function.

# Train the model
glmnet.fit <- cv.glmnet(x=xtrain, y=ytrain, family='binomial', alpha=0)

# Generate predictions
preds <- predict(glmnet.fit, newx=xtest, type='response', s='lambda.min')

# Put results into dataframe for plotting.
results <- data.frame(pred=preds, actual=ytest)


#Let's plot the dual densities. Here we are plotting densities of the predicted probabilites. We do this for all predicted probabilities for each of the true values 0 (down) or 1 (up or unchanged). As suspected there is no good value for the probability threshold. 
#In fact, the predictions cannot be separated at all as they are nearly identical. 



ggplot(results, aes(x=preds, color=actual)) + geom_density()

```

Now let's use the ROCR package to assess performance. First we create two performance objects: one for the true positive/false positive rates, and one for the AUC score. 
```{r}

prediction <- prediction(preds, ytest)
perf <- performance(prediction, measure = "tpr", x.measure = "fpr")

auc <- performance(prediction, measure = "auc")
auc <- auc@y.values[[1]]

```

We have an AUC score of `r auc`. This is not good at all, but is exactly what I suspected. We are doing only a small fraction worse than we would by simply making random guesses. 

Now let's plot the AUC curve.

```{r}

roc.data <- data.frame(fpr=unlist(perf@x.values),
                       tpr=unlist(perf@y.values))


ggplot(roc.data, aes(x=fpr, ymin=0, ymax=tpr)) +
    geom_ribbon(alpha=0.2) +
geom_line(aes(y=tpr)) +
geom_abline(slope=1, intercept=0, linetype='dashed') +
ggtitle("ROC Curve") +
ylab('True Positive Rate') +
xlab('False Positive Rate')
```

It's exactly the identity line, which again means our model is not performing better than a null model of random guesses. Can we do better?

Let's now do the same thing, but this time we will use bigrams rather than individual words. 
We'll use the NGramTokenizer from the RWeka package to build a bigram tokenizer, then feed it to our control list.
We will also set some bounds. We will only use bigrams that appear in at least 20 of the documents. This will eliminated some of the cruft.
We won't use bigrams that appear in more than 500 of the documents. This will keep the size of our DocumentTermMatrix under control, otherwise 
we may run into memory issues. 

```{r}

# Necessary to set this option on Linux machines, otherwise the NGrameTokenizer will cause our 
# DocumentTermMatrix call to hang. 
options(mc.cores=1)

BigramTokenizer <- function(x) NGramTokenizer(x, Weka_control(min = 2, max = 2))

control <- list(
tokenize=BigramTokenizer,
bounds = list(global = c(20, 500))

)

dtm <- Corpus(VectorSource(data$all)) %>%
    tm_map(removeNumbers) %>%
tm_map(stripWhitespace) %>%
tm_map(content_transformer(tolower)) %>%
DocumentTermMatrix(control=control)

```

```{r}

split_index <- data$Date <= '2014-12-31'


ytrain <- as.factor(data$Label[split_index])
xtrain <- Matrix(as.matrix(dtm)[split_index, ], sparse=TRUE)

ytest <- as.factor(data$Label[!split_index])
xtest <- Matrix(as.matrix(dtm)[!split_index, ], sparse=TRUE)

```

Now we can fit a glmnet model exactly the same as before, setting alpha to 0 indicating that we want to use ridge regression.

```{r}

# Train the model
glmnet.fit <- cv.glmnet(x=xtrain, y=ytrain, family='binomial', alpha=0)

# Generate predictions
preds <- predict(glmnet.fit, newx=xtest, type='response', s="lambda.min")

# Put results into dataframe for plotting.
results <- data.frame(pred=preds, actual=ytest)

```

Let's plot the dual densities again. Looks like we may have a little bit of separation this time!
  
  ```{r}

ggplot(results, aes(x=preds, color=actual)) + geom_density()

```

Now let's use the ROCR package to assess performance again.
```{r}

prediction <- prediction(preds, ytest)
perf <- performance(prediction, measure = "tpr", x.measure = "fpr")

auc <- performance(prediction, measure = "auc")
auc <- auc@y.values[[1]]

```

We have an AUC score of `r auc`. Better than the first try and better than random guessing! Keep in mind however
 that we dont know the standard deviation of this score. Its possible that we obtained a score greater than .5 only by chance. 

```{r}

roc.data <- data.frame(fpr=unlist(perf@x.values),
                       tpr=unlist(perf@y.values))

ggplot(roc.data, aes(x=fpr, ymin=0, ymax=tpr)) +
    geom_ribbon(alpha=0.2) +
    geom_line(aes(y=tpr)) +
    geom_abline(slope=1, intercept=0, linetype='dashed') +
    ggtitle("ROC Curve") +
    ylab('True Positive Rate') +
    xlab('False Positive Rate')
```

Looks good. Can we do even better?


### Next Steps

There are several things I'd like to try:
  
  
  1. Use trigrams or even 4grams.
2. Try different models. Naive Bayes and SVM might work well here (assuming the e1071 package algorithms have sparse matrix support. I'm not sure that they do).
3. Try lagging the independnt variables, i.e. using the xth previous day's headlines to predict each day's direction.
4. Try varying the bounds of bigrams to get the most informative ones. 












#https://www.kaggle.com/petrschonbauer/glmnet-and-randomforest-in-r-caret






#https://www.kaggle.com/bwboerman/r-data-table-glmnet-xgboost-with-caret





#https://www.kaggle.com/jimthompson/regularized-linear-models-in-r





#https://www.kaggle.com/bisaria/titanic-lasso-ridge-implementation





#https://www.kaggle.com/bisaria/titanic-lasso-ridge-implementation





#https://www.kaggle.com/janlauge/glmnet-with-feature-engineering






#https://www.kaggle.com/lbronchal/trying-models-rf-svm-nnet-lda-knn-glmnet





#https://www.r-bloggers.com/variable-selection-with-elastic-net/
  
 




