package com.mywebapp.service;

import com.mywebapp.model.Task;
import com.mywebapp.repository.TaskRepository;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;

@Service
public class TaskService {

    private final TaskRepository taskRepository;

    public TaskService(TaskRepository taskRepository) {
        this.taskRepository = taskRepository;
    }

    public List<Task> getAllTasks() {
        return taskRepository.findAll();
    }

    public Task createTask(String title) {
        Task task = new Task();
        task.setTitle(title);
        task.setStatus("pending");
        return taskRepository.save(task);
    }

    public Optional<Task> markDone(Long id) {
        return taskRepository.findById(id).map(task -> {
            task.setStatus("done");
            return taskRepository.save(task);
        });
    }
}
