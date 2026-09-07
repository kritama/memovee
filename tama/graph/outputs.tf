# Public interfaces for the follow-up ingestion, indexing and recall work.
# Resources are declared in the feature files; this output only exposes them.
output "interfaces" {
  value = {
    spaces = {
      "remember"         = module.remember.space_id
      "recall"           = module.recall.space_id
      "memory-write"     = tama_space.memory-write.id
      "memory-query"     = tama_space.memory-query.id
      "memory-index"     = tama_space.memory-index.id
      "memory-api"       = tama_space.memory-api.id
      "memory-inference" = tama_space.memory-inference.id
    }
    roots = {
      remember = module.remember.schemas
      recall   = module.recall.schemas
    }
    stages = {
      "remember-ingestion" = {
        class_id = module.remember-ingestion-request.class.id
        chain_id = tama_chain.remember-ingestion.id
        relation = "ingestion"
        queue_id = tama_queue.interactive.id
      }
      "remember-ingestion-state" = {
        class_id = module.remember-ingestion-state-request.class.id
        chain_id = tama_chain.remember-ingestion-state.id
        relation = "ingestion-state"
        queue_id = tama_queue.interactive.id
      }
      "remember-candidate" = {
        class_id = module.remember-candidate-request.class.id
        chain_id = tama_chain.remember-candidate.id
        relation = "candidate"
        queue_id = tama_queue.interactive.id
      }
      "remember-save" = {
        class_id = module.remember-save-request.class.id
        chain_id = tama_chain.remember-save.id
        relation = "save"
        queue_id = tama_queue.interactive.id
      }
      "remember-status" = {
        class_id = module.remember-status-request.class.id
        chain_id = tama_chain.remember-status.id
        relation = "status"
        queue_id = tama_queue.interactive.id
      }
      "remember-recovery-state" = {
        class_id = module.remember-recovery-state-request.class.id
        chain_id = tama_chain.remember-recovery-state.id
        relation = "recovery-state"
        queue_id = tama_queue.interactive.id
      }
      "remember-retry-save" = {
        class_id = module.remember-retry-save-request.class.id
        chain_id = tama_chain.remember-retry-save.id
        relation = "retry-save"
        queue_id = tama_queue.interactive.id
      }
      "remember-receipt" = {
        class_id = module.remember-receipt-request.class.id
        chain_id = tama_chain.remember-receipt.id
        relation = "receipt"
        queue_id = tama_queue.interactive.id
      }
      "remember-clarification" = {
        class_id = module.remember-clarification-request.class.id
        chain_id = tama_chain.remember-clarification.id
        relation = "clarification"
        queue_id = tama_queue.interactive.id
      }
      "remember-failure" = {
        class_id = module.remember-failure-request.class.id
        chain_id = tama_chain.remember-failure.id
        relation = "failure"
        queue_id = tama_queue.interactive.id
      }
      "remember-invalid-response" = {
        class_id = module.remember-invalid-response-request.class.id
        chain_id = tama_chain.remember-invalid-response.id
        relation = "invalid-response"
        queue_id = tama_queue.interactive.id
      }
      "remember-invalid-candidate" = {
        class_id = module.remember-invalid-candidate-request.class.id
        chain_id = tama_chain.remember-invalid-candidate.id
        relation = "invalid-candidate"
        queue_id = tama_queue.interactive.id
      }
      "remember-save-unconfirmed" = {
        class_id = module.remember-save-unconfirmed-request.class.id
        chain_id = tama_chain.remember-save-unconfirmed.id
        relation = "save-unconfirmed"
        queue_id = tama_queue.interactive.id
      }
      "recall-query" = {
        class_id = module.recall-query-request.class.id
        chain_id = tama_chain.recall-query.id
        relation = "query"
        queue_id = tama_queue.interactive.id
      }
      "recall-strategy" = {
        class_id = module.recall-strategy-request.class.id
        chain_id = tama_chain.recall-strategy.id
        relation = "strategy"
        queue_id = tama_queue.interactive.id
      }
      "recall-query-embedding" = {
        class_id = module.recall-query-embedding-request.class.id
        chain_id = tama_chain.recall-query-embedding.id
        relation = "query-embedding"
        queue_id = tama_queue.interactive.id
      }
      "recall-search" = {
        class_id = module.recall-search-request.class.id
        chain_id = tama_chain.recall-search.id
        relation = "search"
        queue_id = tama_queue.interactive.id
      }
      "recall-search-status" = {
        class_id = module.recall-search-status-request.class.id
        chain_id = tama_chain.recall-search-status.id
        relation = "search-status"
        queue_id = tama_queue.interactive.id
      }
      "recall-answer" = {
        class_id = module.recall-answer-request.class.id
        chain_id = tama_chain.recall-answer.id
        relation = "answer"
        queue_id = tama_queue.interactive.id
      }
      "recall-result" = {
        class_id = module.recall-result-request.class.id
        chain_id = tama_chain.recall-result.id
        relation = "result"
        queue_id = tama_queue.interactive.id
      }
      "recall-clarification" = {
        class_id = module.recall-clarification-request.class.id
        chain_id = tama_chain.recall-clarification.id
        relation = "clarification"
        queue_id = tama_queue.interactive.id
      }
      "recall-failure" = {
        class_id = module.recall-failure-request.class.id
        chain_id = tama_chain.recall-failure.id
        relation = "failure"
        queue_id = tama_queue.interactive.id
      }
      "recall-invalid-query" = {
        class_id = module.recall-invalid-query-request.class.id
        chain_id = tama_chain.recall-invalid-query.id
        relation = "invalid-query"
        queue_id = tama_queue.interactive.id
      }
      "recall-invalid-response" = {
        class_id = module.recall-invalid-response-request.class.id
        chain_id = tama_chain.recall-invalid-response.id
        relation = "invalid-response"
        queue_id = tama_queue.interactive.id
      }
      "recall-invalid-evidence" = {
        class_id = module.recall-invalid-evidence-request.class.id
        chain_id = tama_chain.recall-invalid-evidence.id
        relation = "invalid-evidence"
        queue_id = tama_queue.interactive.id
      }
      "index-snapshot" = {
        class_id = module.index-snapshot-request.class.id
        chain_id = tama_chain.index-snapshot.id
        relation = "snapshot"
        queue_id = tama_queue.index.id
      }
      "index-description" = {
        class_id = module.index-description-request.class.id
        chain_id = tama_chain.index-description.id
        relation = "description"
        queue_id = tama_queue.index.id
      }
      "index-embedding-inputs" = {
        class_id = module.index-embedding-inputs-request.class.id
        chain_id = tama_chain.index-embedding-inputs.id
        relation = "embedding-inputs"
        queue_id = tama_queue.index.id
      }
      "index-embeddings" = {
        class_id = module.index-embeddings-request.class.id
        chain_id = tama_chain.index-embeddings.id
        relation = "embeddings"
        queue_id = tama_queue.index.id
      }
      "index-completion" = {
        class_id = module.index-completion-request.class.id
        chain_id = tama_chain.index-completion.id
        relation = "completion"
        queue_id = tama_queue.index.id
      }
      "index-failure" = {
        class_id = module.index-failure-request.class.id
        chain_id = tama_chain.index-failure.id
        relation = "failure"
        queue_id = tama_queue.index.id
      }
      "memory-write" = {
        class_id = module.memory-write-request.class.id
        chain_id = tama_chain.memory-write.id
        relation = "ingestion"
        queue_id = tama_queue.interactive.id
      }
      "memory-query" = {
        class_id = module.memory-query-request.class.id
        chain_id = tama_chain.memory-query.id
        relation = "query"
        queue_id = tama_queue.interactive.id
      }
      "memory-projection" = {
        class_id = tama_class.memory-projection-request.id
        chain_id = tama_chain.memory-projection.id
        relation = "snapshot"
        queue_id = tama_queue.index.id
      }
    }
    results = {
      remember = {
        request_class_id = module.remember-result-publication-request.class.id
        class_id         = tama_class.remember-result.id
        chain_id         = tama_chain.remember-result-delivery.id
      }
      recall = {
        request_class_id = module.recall-result-publication-request.class.id
        class_id         = tama_class.recall-result.id
        chain_id         = tama_chain.recall-result-delivery.id
      }
    }
    global_space_id            = var.global_space_id
    context_metadata_corpus_id = var.context_metadata_corpus_id
    action_call_json_corpus_id = var.action_call_json_corpus_id
    completion_model_id        = module.inference.model_ids["openai/gpt-4.1-mini"]
    ready                      = false
  }
}
